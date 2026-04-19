import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let diskDiscovery = DiskDiscoveryService()
    private let smartctl = SmartctlService()
    private let historyStore = InspectionHistoryStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var lastMissingToolRecheckAt: Date?
    @ObservationIgnored private let missingToolRecheckCooldown: TimeInterval = 6
    @ObservationIgnored private var selfTestRefreshTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let selfTestRefreshInterval: Duration = .seconds(10)
    @ObservationIgnored private var pendingSelfTestKindByDevice: [String: SmartSelfTestKind] = [:]

    var snapshots: [DriveSnapshot] = []
    var historyByDevice: [String: [HistoricalDriveSnapshot]] = [:]
    var activityByDevice: [String: DriveActivity] = [:]
    var currentTaskByDevice: [String: DriveTask] = [:]
    var recentTaskByDevice: [String: DriveTask] = [:]
    var selection: String?
    var searchText = ""
    var isRefreshing = false
    var lastRefreshError: String?
    var smartctlPathOverride: String
    var preferAdministratorAccess: Bool

    init() {
        smartctlPathOverride = defaults.string(forKey: "smartctlPathOverride") ?? ""
        preferAdministratorAccess = defaults.bool(forKey: "preferAdministratorAccess")
        historyByDevice = (try? historyStore.loadAll()) ?? [:]
    }

    var filteredSnapshots: [DriveSnapshot] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return snapshots
        }

        let query = searchText.lowercased()
        return snapshots.filter { snapshot in
            snapshot.device.displayName.lowercased().contains(query)
                || snapshot.device.deviceIdentifier.lowercased().contains(query)
                || snapshot.device.subtitle.lowercased().contains(query)
        }
    }

    var selectedSnapshot: DriveSnapshot? {
        guard let selection else {
            return filteredSnapshots.first
        }

        return snapshots.first(where: { $0.id == selection })
    }

    func activity(for deviceIdentifier: String) -> DriveActivity {
        activityByDevice[deviceIdentifier] ?? .idle
    }

    func currentTask(for deviceIdentifier: String) -> DriveTask? {
        currentTaskByDevice[deviceIdentifier]
    }

    func recentTask(for deviceIdentifier: String) -> DriveTask? {
        recentTaskByDevice[deviceIdentifier]
    }

    func refresh(forcePrivilegePrompt: Bool = false) async {
        isRefreshing = true
        lastRefreshError = nil

        defer {
            isRefreshing = false
            defaults.set(smartctlPathOverride, forKey: "smartctlPathOverride")
            defaults.set(preferAdministratorAccess, forKey: "preferAdministratorAccess")
        }

        do {
            let devices = try await diskDiscovery.discoverDevices()
            snapshots = devices.map { DriveSnapshot(device: $0, inspectionState: .loading) }
            for device in devices {
                setRefreshTask(
                    for: device.id,
                    admin: forcePrivilegePrompt || preferAdministratorAccess
                )
            }

            if selection == nil || !snapshots.contains(where: { $0.id == selection }) {
                selection = snapshots.first?.id
            }

            let shouldPromptForAdmin = forcePrivilegePrompt || preferAdministratorAccess
            if shouldPromptForAdmin {
                let states = try await smartctl.inspectManyWithAdministratorPrompt(
                    devices: devices,
                    preferredPath: smartctlPathOverride
                )
                for device in devices {
                    updateInspectionState(
                        states[device.id] ?? .unavailable(
                            UserFacingIssue(
                                kind: .commandFailed,
                                title: "SMART Read Failed",
                                message: "No response was captured for \(device.displayName).",
                                recoverySuggestion: "Try again with administrator access."
                            )
                        ),
                        for: device.id
                    )
                }
            } else {
                for device in devices {
                    let state = try await smartctl.inspect(
                        device: device,
                        preferredPath: smartctlPathOverride,
                        useAdministratorPrompt: false
                    )
                    updateInspectionState(state, for: device.id)
                }
            }

            if devices.isEmpty {
                lastRefreshError = "No physical disks were found."
            }
        } catch {
            lastRefreshError = error.localizedDescription
            snapshots = []
        }
    }

    func refreshSelection(forcePrivilegePrompt: Bool = false) async {
        guard let selectedSnapshot else {
            await refresh(forcePrivilegePrompt: forcePrivilegePrompt)
            return
        }

        await refreshDevice(
            identifier: selectedSnapshot.id,
            forcePrivilegePrompt: forcePrivilegePrompt,
            respectAdminPreference: true
        )
    }

    private func refreshDevice(
        identifier: String,
        forcePrivilegePrompt: Bool,
        respectAdminPreference: Bool
    ) async {
        guard let snapshot = snapshots.first(where: { $0.id == identifier }) else {
            return
        }

        do {
            let usingAdmin = forcePrivilegePrompt || (respectAdminPreference && preferAdministratorAccess)
            setRefreshTask(for: snapshot.id, admin: usingAdmin)
            updateInspectionState(.loading, for: snapshot.id)
            let state = try await smartctl.inspect(
                device: snapshot.device,
                preferredPath: smartctlPathOverride,
                useAdministratorPrompt: usingAdmin
            )
            updateInspectionState(state, for: snapshot.id)
        } catch {
            updateInspectionState(
                .unavailable(
                    UserFacingIssue(
                        kind: .commandFailed,
                        title: "Refresh Failed",
                        message: error.localizedDescription,
                        recoverySuggestion: "Check the smartctl path and try again."
                    )
                ),
                for: snapshot.id
            )
        }
    }

    func recheckMissingSmartctlIfNeeded() async {
        guard !isRefreshing else {
            return
        }

        guard let selectedSnapshot else {
            return
        }

        guard case let .unavailable(issue) = selectedSnapshot.inspectionState,
              issue.kind == .smartctlMissing else {
            return
        }

        let now = Date()
        if let lastMissingToolRecheckAt,
           now.timeIntervalSince(lastMissingToolRecheckAt) < missingToolRecheckCooldown {
            return
        }

        lastMissingToolRecheckAt = now
        await refreshSelection()
    }

    func runSelfTest(_ kind: SmartSelfTestKind) async {
        guard let selectedSnapshot else {
            return
        }

        do {
            pendingSelfTestKindByDevice[selectedSnapshot.id] = kind
            let result = try await smartctl.runSelfTest(
                on: selectedSnapshot.device,
                kind: kind,
                preferredPath: smartctlPathOverride,
                useAdministratorPrompt: true
            )

            switch result {
            case let .success(info):
                if selectedSnapshot.device.isInternal {
                    setTask(
                        DriveTask(
                            deviceIdentifier: selectedSnapshot.id,
                            kind: .selfTest(kind),
                            state: .waitingForAdmin,
                            title: "\(kind.title) started",
                            detail: "Use Refresh as Admin to check progress or confirm the result on this drive.",
                            startedAt: Date(),
                            updatedAt: Date(),
                            progressRemaining: nil
                        ),
                        for: selectedSnapshot.id
                    )
                } else {
                    setTask(
                        DriveTask(
                            deviceIdentifier: selectedSnapshot.id,
                            kind: .selfTest(kind),
                            state: .running,
                            title: "\(kind.title) started",
                            detail: info.userMessage,
                            startedAt: Date(),
                            updatedAt: Date(),
                            progressRemaining: nil
                        ),
                        for: selectedSnapshot.id
                    )
                }
                if !selectedSnapshot.device.isInternal {
                    await refreshDevice(
                        identifier: selectedSnapshot.id,
                        forcePrivilegePrompt: false,
                        respectAdminPreference: false
                    )
                }
            case let .failure(issue):
                recentTaskByDevice[selectedSnapshot.id] = DriveTask(
                    deviceIdentifier: selectedSnapshot.id,
                    kind: .selfTest(kind),
                    state: .failed,
                    title: issue.title,
                    detail: issue.message,
                    startedAt: Date(),
                    updatedAt: Date(),
                    progressRemaining: nil
                )
                currentTaskByDevice[selectedSnapshot.id] = nil
                pendingSelfTestKindByDevice[selectedSnapshot.id] = nil
                updateActivityFromTask(for: selectedSnapshot.id)
            }
        } catch {
            recentTaskByDevice[selectedSnapshot.id] = DriveTask(
                deviceIdentifier: selectedSnapshot.id,
                kind: .selfTest(kind),
                state: .failed,
                title: "Self-test failed to start",
                detail: error.localizedDescription,
                startedAt: Date(),
                updatedAt: Date(),
                progressRemaining: nil
            )
            currentTaskByDevice[selectedSnapshot.id] = nil
            pendingSelfTestKindByDevice[selectedSnapshot.id] = nil
            updateActivityFromTask(for: selectedSnapshot.id)
        }
    }

    func history(for deviceIdentifier: String) -> [HistoricalDriveSnapshot] {
        historyByDevice[deviceIdentifier] ?? []
    }

    func comparisonBaseline(
        for deviceIdentifier: String,
        currentCapturedAt: Date
    ) -> HistoricalDriveSnapshot? {
        let entries = history(for: deviceIdentifier)

        guard let last = entries.last else {
            return nil
        }

        if abs(last.capturedAt.timeIntervalSince(currentCapturedAt)) < 1 {
            return entries.dropLast().last
        }

        return last
    }

    func recentHistory(for deviceIdentifier: String, limit: Int = 5) -> [HistoricalDriveSnapshot] {
        Array(history(for: deviceIdentifier).suffix(limit).reversed())
    }

    private func updateInspectionState(_ state: InspectionState, for identifier: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == identifier }) else {
            return
        }

        let previousInspection: DeviceInspection? = {
            if case let .loaded(inspection) = snapshots[index].inspectionState {
                return inspection
            }
            return nil
        }()

        snapshots[index].inspectionState = state

        if case let .loaded(inspection) = state {
            handleLoadedInspection(
                inspection,
                previousInspection: previousInspection,
                for: identifier,
                device: snapshots[index].device
            )
            manageSelfTestRefresh(for: identifier, inspection: inspection)
            recordHistory(for: snapshots[index].device, inspection: inspection)
        } else if case let .unavailable(issue) = state {
            handleUnavailableState(issue, for: identifier, device: snapshots[index].device)
        }
    }

    private func handleLoadedInspection(
        _ inspection: DeviceInspection,
        previousInspection: DeviceInspection?,
        for identifier: String,
        device: StorageDevice
    ) {
        let previousStatus = previousInspection?.selfTestStatusInfo
        let currentStatus = inspection.selfTestStatusInfo
        let pendingKind = pendingSelfTestKindByDevice[identifier]

        if let currentStatus, currentStatus.isInProgress {
            let taskKind = pendingKind.map(DriveTaskKind.selfTest) ?? inferredSelfTestKind(for: identifier)
            setTask(
                DriveTask(
                    deviceIdentifier: identifier,
                    kind: taskKind,
                    state: .running,
                    title: currentStatus.title,
                    detail: currentStatus.detail,
                    startedAt: currentTaskByDevice[identifier]?.startedAt ?? Date(),
                    updatedAt: inspection.capturedAt,
                    progressRemaining: currentStatus.progressRemaining
                ),
                for: identifier
            )
            return
        }

        if previousStatus?.isInProgress == true, let currentStatus, currentStatus.isFinished {
            completeSelfTestTask(
                for: identifier,
                kind: pendingKind ?? inferredSelfTestKind(for: identifier).selfTestKind ?? .short,
                with: currentStatus,
                at: inspection.capturedAt
            )
            return
        }

        if let task = currentTaskByDevice[identifier],
           task.state == .waitingForAdmin,
           device.isInternal,
           currentStatus == nil {
            updateActivityFromTask(for: identifier)
            return
        }

        if isRefreshTask(currentTaskByDevice[identifier]) {
            currentTaskByDevice[identifier] = nil
        }

        updateActivityFromTask(for: identifier)
    }

    private func manageSelfTestRefresh(for identifier: String, inspection: DeviceInspection) {
        guard let status = inspection.selfTestStatusInfo, status.isInProgress else {
            selfTestRefreshTasks[identifier]?.cancel()
            selfTestRefreshTasks[identifier] = nil
            return
        }

        if selfTestRefreshTasks[identifier] != nil {
            return
        }

        selfTestRefreshTasks[identifier] = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: self.selfTestRefreshInterval)
                guard !Task.isCancelled else { break }

                let shouldContinue = await MainActor.run { () -> Bool in
                    guard let snapshot = self.snapshots.first(where: { $0.id == identifier }),
                          case let .loaded(inspection) = snapshot.inspectionState else {
                        return false
                    }

                    return inspection.selfTestStatusInfo?.isInProgress == true
                }

                guard shouldContinue else { break }
                await self.refreshDevice(
                    identifier: identifier,
                    forcePrivilegePrompt: false,
                    respectAdminPreference: false
                )
            }

            await MainActor.run {
                self.selfTestRefreshTasks[identifier] = nil
            }
        }
    }

    private func recordHistory(for device: StorageDevice, inspection: DeviceInspection) {
        let snapshot = HistoricalDriveSnapshot(
            deviceIdentifier: device.deviceIdentifier,
            capturedAt: inspection.capturedAt,
            health: inspection.health,
            temperatureC: inspection.summary.temperatureC,
            powerOnHours: inspection.summary.powerOnHours,
            percentageUsed: inspection.summary.percentageUsed,
            availableSpare: inspection.summary.availableSpare,
            selfTestStatus: inspection.summary.selfTestStatus,
            alertsCount: inspection.alerts.count
        )

        historyByDevice = (try? historyStore.record(snapshot, in: historyByDevice)) ?? historyByDevice
    }

    private func setActivity(_ activity: DriveActivity, for identifier: String) {
        activityByDevice[identifier] = activity
    }

    private func setTask(_ task: DriveTask, for identifier: String) {
        currentTaskByDevice[identifier] = task
        recentTaskByDevice[identifier] = nil
        updateActivityFromTask(for: identifier)
    }

    private func setRefreshTask(for identifier: String, admin: Bool) {
        let existingStart = currentTaskByDevice[identifier]?.startedAt ?? Date()
        currentTaskByDevice[identifier] = DriveTask(
            deviceIdentifier: identifier,
            kind: .refresh(admin: admin),
            state: .running,
            title: admin ? "Refreshing with admin access" : "Refreshing drive status",
            detail: admin ? "Reading detailed SMART data with administrator access." : "Reading SMART data and updating health details.",
            startedAt: existingStart,
            updatedAt: Date(),
            progressRemaining: nil
        )
        updateActivityFromTask(for: identifier)
    }

    private func completeSelfTestTask(
        for identifier: String,
        kind: SmartSelfTestKind,
        with status: SelfTestStatusInfo,
        at date: Date
    ) {
        let state: DriveTaskState
        switch status.kind {
        case .passed:
            state = .succeeded
        case .failed, .aborted:
            state = .failed
        case .running, .unknown:
            state = .succeeded
        }

        recentTaskByDevice[identifier] = DriveTask(
            deviceIdentifier: identifier,
            kind: .selfTest(kind),
            state: state,
            title: status.title,
            detail: status.detail,
            startedAt: currentTaskByDevice[identifier]?.startedAt ?? date,
            updatedAt: date,
            progressRemaining: nil
        )
        currentTaskByDevice[identifier] = nil
        pendingSelfTestKindByDevice[identifier] = nil
        updateActivityFromTask(for: identifier)
    }

    private func handleUnavailableState(
        _ issue: UserFacingIssue,
        for identifier: String,
        device: StorageDevice
    ) {
        if issue.kind == .permissionRequired,
           let task = currentTaskByDevice[identifier],
           task.kind.isSelfTest,
           device.isInternal {
            var updatedTask = task
            updatedTask.state = .waitingForAdmin
            updatedTask.title = "\(task.kind.title) started"
            updatedTask.detail = "Refresh as Admin to check progress or confirm the result on this drive."
            updatedTask.updatedAt = Date()
            updatedTask.progressRemaining = nil
            currentTaskByDevice[identifier] = updatedTask
            updateActivityFromTask(for: identifier)
            return
        }

        if let task = currentTaskByDevice[identifier], isRefreshTask(task) {
            recentTaskByDevice[identifier] = DriveTask(
                deviceIdentifier: identifier,
                kind: task.kind,
                state: .failed,
                title: task.kind.title,
                detail: issue.message,
                startedAt: task.startedAt,
                updatedAt: Date(),
                progressRemaining: nil
            )
            currentTaskByDevice[identifier] = nil
        }

        updateActivityFromTask(for: identifier)
    }

    private func updateActivityFromTask(for identifier: String) {
        guard let task = currentTaskByDevice[identifier] else {
            setActivity(.idle, for: identifier)
            return
        }

        switch task.state {
        case .running:
            if task.kind.isSelfTest {
                setActivity(.selfTestRunning, for: identifier)
            } else {
                setActivity(.refreshing, for: identifier)
            }
        case .waitingForAdmin:
            setActivity(.awaitingAdminRefresh, for: identifier)
        case .succeeded, .failed:
            setActivity(.idle, for: identifier)
        }
    }

    private func isRefreshTask(_ task: DriveTask?) -> Bool {
        guard let task else {
            return false
        }
        return isRefreshTask(task)
    }

    private func isRefreshTask(_ task: DriveTask) -> Bool {
        if case .refresh = task.kind {
            return true
        }
        return false
    }

    private func inferredSelfTestKind(for identifier: String) -> DriveTaskKind {
        if let task = currentTaskByDevice[identifier]?.kind {
            switch task {
            case .selfTest:
                return task
            case .refresh:
                break
            }
        }

        if let kind = pendingSelfTestKindByDevice[identifier] {
            return .selfTest(kind)
        }

        if let recentTask = recentTaskByDevice[identifier]?.kind {
            switch recentTask {
            case .selfTest:
                return recentTask
            case .refresh:
                break
            }
        }

        return .selfTest(.short)
    }
}
