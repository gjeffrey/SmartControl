import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let diskDiscovery = DiskDiscoveryService()
    private let smartctl = SmartctlService()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var lastMissingToolRecheckAt: Date?
    @ObservationIgnored private let missingToolRecheckCooldown: TimeInterval = 6

    var snapshots: [DriveSnapshot] = []
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

            if selection == nil || !snapshots.contains(where: { $0.id == selection }) {
                selection = snapshots.first?.id
            }

            let shouldPromptForAdmin = forcePrivilegePrompt || preferAdministratorAccess
            for device in devices {
                let state = try await smartctl.inspect(
                    device: device,
                    preferredPath: smartctlPathOverride,
                    useAdministratorPrompt: shouldPromptForAdmin
                )
                updateInspectionState(state, for: device.id)
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

        do {
            updateInspectionState(.loading, for: selectedSnapshot.id)
            let state = try await smartctl.inspect(
                device: selectedSnapshot.device,
                preferredPath: smartctlPathOverride,
                useAdministratorPrompt: forcePrivilegePrompt || preferAdministratorAccess
            )
            updateInspectionState(state, for: selectedSnapshot.id)
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
                for: selectedSnapshot.id
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
            case let .success(message):
                lastActionMessage = message
                await refreshSelection(forcePrivilegePrompt: true)
            case let .failure(issue):
                lastActionMessage = "\(issue.title): \(issue.message)"
            }
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    private func updateInspectionState(_ state: InspectionState, for identifier: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == identifier }) else {
            return
        }

        snapshots[index].inspectionState = state
    }
}
