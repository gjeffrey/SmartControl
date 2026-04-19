import Observation
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.filteredSnapshots) { snapshot in
                SidebarRow(snapshot: snapshot)
                    .tag(snapshot.id)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Drives")
        .overlay {
            if model.snapshots.isEmpty && !model.isRefreshing {
                ContentUnavailableView(
                    "No Drives Found",
                    systemImage: "internaldrive",
                    description: Text(model.lastRefreshError ?? "Connect a supported disk or refresh the list.")
                )
            }
        }
    }
}

private struct SidebarRow: View {
    let snapshot: DriveSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snapshot.device.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(statusColor, .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.device.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(statusTitle)
                }

                Text(snapshot.device.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.device.displayName), \(statusTitle)")
    }

    private var statusTitle: String {
        switch snapshot.inspectionState {
        case .loading:
            return "Refreshing"
        case let .loaded(inspection):
            return inspection.health.title
        case let .unavailable(issue):
            switch issue.kind {
            case .permissionRequired:
                return "Needs Administrator Access"
            case .smartctlMissing:
                return "smartctl Missing"
            case .commandFailed:
                return "Read Failed"
            }
        }
    }

    private var statusColor: Color {
        switch snapshot.inspectionState {
        case .loading:
            return .secondary
        case let .loaded(inspection):
            switch inspection.health {
            case .healthy:
                return .green
            case .caution:
                return .orange
            case .critical:
                return .red
            case .unknown:
                return .secondary
            }
        case let .unavailable(issue):
            switch issue.kind {
            case .permissionRequired:
                return .orange
            case .smartctlMissing:
                return .secondary
            case .commandFailed:
                return .red
            }
        }
    }
}
