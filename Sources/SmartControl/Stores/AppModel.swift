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
    @ObservationIgnored private var selfTestRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeSelfTestDeviceIdentifier: String?
    @ObservationIgnored private let selfTestRefreshInterval: Duration = .seconds(10)

    var snapshots: [DriveSnapshot] = []
    var historyByDevice: [String: [HistoricalDriveSnapshot]] = [:]
    var activityByDevice: [String: DriveActivity] = [:]
    var selection: String?
    var searchText = ""
    var isRefreshing = false
    var lastRefreshError: String?
    var lastActionMessage: String?
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

    func refresh(forcePrivilegePrompt: Bool = false) async {
        isRefreshing = true
        lastRefreshError = nil
        lastActionMessage = nil

        defer {
            isRefreshing = false
            defaults.set(smartctlPathOverride, forKey: "smartctlPathOverride")
            defaults.set(preferAdministratorAccess, forKey: "preferAdministratorAccess")
        }

        do {
            let devices = try await diskDiscovery.discoverDevices()
            snapshots = devices.map { DriveSnapshot(device: $0, inspectionState: .loading) }
            for device in devices {
                activityByDevice[device.id] = .refreshing
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
            setActivity(.refreshing, for: snapshot.id)
            updateInspectionState(.loading, for: snapshot.id)
            let state = try await smartctl.inspect(
                device: snapshot.device,
                preferredPath: smartctlPathOverride,
                useAdministratorPrompt: forcePrivilegePrompt || (respectAdminPreference && preferAdministratorAccess)
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
            let result = try await smartctl.runSelfTest(
                on: selectedSnapshot.device,
                kind: kind,
                preferredPath: smartctlPathOverride,
                useAdministratorPrompt: true
            )

            switch result {
            case let .success(info):
                lastActionMessage = info.userMessage
                setActivity(selectedSnapshot.device.isInternal ? .awaitingAdminRefresh : .selfTestRunning, for: selectedSnapshot.id)
                if !selectedSnapshot.device.isInternal {
                    await refreshDevice(
                        identifier: selectedSnapshot.id,
                        forcePrivilegePrompt: false,
                        respectAdminPreference: false
                    )
                }
            case let .failure(issue):
                lastActionMessage = "\(issue.title): \(issue.message)"
            }
        } catch {
            lastActionMessage = error.localizedDescription
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
            updateActivityAfterLoadedState(
                inspection: inspection,
                for: identifier,
                device: snapshots[index].device
            )
            handleSelfTestTransition(from: previousInspection, to: inspection)
            manageSelfTestRefresh(for: identifier, inspection: inspection)
            recordHistory(for: snapshots[index].device, inspection: inspection)
        } else if case .unavailable = state, activity(for: identifier) == .refreshing {
            setActivity(.idle, for: identifier)
        }
    }

    private func handleSelfTestTransition(from previous: DeviceInspection?, to current: DeviceInspection) {
        let previousStatus = previous?.selfTestStatusInfo
        let currentStatus = current.selfTestStatusInfo

        if previousStatus?.isInProgress == true, let currentStatus, currentStatus.isFinished {
            lastActionMessage = currentStatus.kind == .passed
                ? "Self-test completed without error."
                : currentStatus.detail
        }
    }

    private func manageSelfTestRefresh(for identifier: String, inspection: DeviceInspection) {
        guard let status = inspection.selfTestStatusInfo, status.isInProgress else {
            if activeSelfTestDeviceIdentifier == identifier {
                selfTestRefreshTask?.cancel()
                selfTestRefreshTask = nil
                activeSelfTestDeviceIdentifier = nil
            }
            return
        }

        setActivity(.selfTestRunning, for: identifier)

        if activeSelfTestDeviceIdentifier == identifier, selfTestRefreshTask != nil {
            return
        }

        selfTestRefreshTask?.cancel()
        activeSelfTestDeviceIdentifier = identifier
        selfTestRefreshTask = Task { [weak self] in
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
                if self.activeSelfTestDeviceIdentifier == identifier {
                    self.selfTestRefreshTask = nil
                    self.activeSelfTestDeviceIdentifier = nil
                }
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

    private func updateActivityAfterLoadedState(
        inspection: DeviceInspection,
        for identifier: String,
        device: StorageDevice
    ) {
        if inspection.selfTestStatusInfo?.isInProgress == true {
            setActivity(.selfTestRunning, for: identifier)
            return
        }

        if activity(for: identifier) == .awaitingAdminRefresh,
           device.isInternal,
           inspection.selfTestStatusInfo == nil {
            return
        }

        setActivity(.idle, for: identifier)
    }
}
