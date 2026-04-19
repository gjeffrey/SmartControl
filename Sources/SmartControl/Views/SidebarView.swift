import Observation
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.filteredSnapshots) { snapshot in
                    SidebarRow(
                        snapshot: snapshot,
                        activity: model.activity(for: snapshot.id),
                        task: model.currentTask(for: snapshot.id),
                        isSelected: model.selection == snapshot.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selection = snapshot.id
                    }
                }
            }

            if !model.attentionItems.isEmpty {
                Section("Attention") {
                    ForEach(model.attentionItems) { item in
                        AttentionRow(item: item, isSelected: model.selection == item.deviceIdentifier)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = item.deviceIdentifier
                            }
                    }
                }
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
    let activity: DriveActivity
    let task: DriveTask?
    let isSelected: Bool

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

                    activityIndicator
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.device.displayName), \(activityTitle)")
    }

    @ViewBuilder
    private var activityIndicator: some View {
        switch activity {
        case .idle:
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(statusTitle)
        case .refreshing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
                .accessibilityLabel("Refreshing")
        case .selfTestRunning:
            ProgressView()
                .controlSize(.mini)
                .tint(.blue)
                .frame(width: 10, height: 10)
                .accessibilityLabel("Self-test running")
        case .awaitingAdminRefresh:
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Waiting for admin refresh")
        }
    }

    private var activityTitle: String {
        activity == .idle ? statusTitle : activity.title
    }

    private var subtitle: String {
        guard let task else {
            return snapshot.device.subtitle
        }

        switch task.state {
        case .running:
            return task.title
        case .waitingForAdmin:
            return "Needs admin to check progress"
        case .succeeded, .failed:
            return snapshot.device.subtitle
        }
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

private struct AttentionRow: View {
    let item: AttentionItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.severity == .critical ? "exclamationmark.octagon.fill" : "bell.badge.fill")
                .foregroundStyle(item.severity == .critical ? .red : .orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.deviceName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        )
    }
}
