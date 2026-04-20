import AppKit
import Observation
import SwiftUI

struct DriveDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let snapshot = model.selectedSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroCard(for: snapshot)
                        if shouldShowActivityCard(for: snapshot) {
                            activityCard(for: snapshot)
                        }

                        switch snapshot.inspectionState {
                        case .loading:
                            SectionCard("Reading SMART Data") {
                                ProgressView("Collecting structured health data…")
                                    .controlSize(.large)
                            }
                        case let .loaded(inspection):
                            if shouldShowSelfTestCard(for: snapshot, inspection: inspection) {
                                selfTestCard(for: inspection)
                            }
                            changeSummaryCard(for: snapshot.device, inspection: inspection)
                            recentEventsCard(for: snapshot.device)
                            metricsCard(for: snapshot, inspection: inspection)
                            systemContextCard(for: snapshot.device)
                            actionCard(for: snapshot, inspection: inspection)
                            historyCard(for: inspection, device: snapshot.device)
                            volumesCard(for: snapshot.device)

                            if !inspection.attributes.isEmpty {
                                attributesCard(for: inspection)
                            }

                            rawOutputCard(for: inspection)
                        case let .unavailable(issue):
                            unavailableCard(issue: issue, device: snapshot.device)
                            volumesCard(for: snapshot.device)
                        }
                    }
                    .padding(26)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView(
                    "Select a Drive",
                    systemImage: "internaldrive",
                    description: Text("Choose a disk from the sidebar to inspect its SMART data.")
                )
            }
        }
        .navigationTitle(model.selectedSnapshot?.device.displayName ?? "SmartControl")
    }

    @ViewBuilder
    private func heroCard(for snapshot: DriveSnapshot) -> some View {
        let device = snapshot.device

        SectionCard("") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: device.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.primary, .secondary)
                        .frame(width: 52, height: 52)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        statusBadge(for: snapshot)

                        Text(device.displayName)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))

                        Text(device.subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Formatters.capacity(device.sizeBytes))
                            .font(.title2.weight(.semibold))
                        Text(device.deviceNode)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.lastRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for snapshot: DriveSnapshot) -> some View {
        let configuration = badgeConfiguration(for: snapshot)

        Text(configuration.title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.color.opacity(0.14), in: Capsule())
            .foregroundStyle(configuration.color)
    }

    private func badgeConfiguration(for snapshot: DriveSnapshot) -> (title: String, color: Color) {
        switch snapshot.inspectionState {
        case .loading:
            return ("Refreshing", .secondary)
        case let .loaded(inspection):
            switch inspection.health {
            case .healthy:
                return ("Healthy", .green)
            case .caution:
                return ("Needs Attention", .orange)
            case .critical:
                return ("Critical", .red)
            case .unknown:
                return ("Unknown", .secondary)
            }
        case let .unavailable(issue):
            switch issue.kind {
            case .permissionRequired:
                return ("Needs Admin", .orange)
            case .smartctlMissing:
                return ("Setup Needed", .secondary)
            case .commandFailed:
                return ("Read Failed", .red)
            }
        }
    }

    private func activityCard(for snapshot: DriveSnapshot) -> some View {
        let task = model.currentTask(for: snapshot.id) ?? model.recentTask(for: snapshot.id)

        return SectionCard(model.currentTask(for: snapshot.id) == nil ? "Recent Activity" : "Current Activity") {
            if let task {
                if task.state == .running, case .refresh = task.kind {
                    refreshActivityView(task: task)
                } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: taskIcon(task))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(taskColor(task))
                            .frame(width: 40, height: 40)
                            .background(taskColor(task).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.title3.weight(.semibold))
                            Text(task.detail)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(Formatters.refreshTime(task.updatedAt))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }

                    if task.state == .running, let remaining = task.progressRemaining {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(100 - remaining), total: 100)
                                .tint(taskColor(task))
                            Text("About \(remaining)% remains. SmartControl will check again automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if task.state == .waitingForAdmin {
                        HStack(spacing: 12) {
                            Button {
                                Task { await model.refreshSelection(forcePrivilegePrompt: true) }
                            } label: {
                                Label("Check Progress as Admin", systemImage: "lock.open")
                            }
                            .buttonStyle(.borderedProminent)

                            Text("Internal drives often need administrator access before macOS will reveal self-test progress or results.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if task.state == .succeeded {
                        Label("The most recent task finished successfully.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else if task.state == .failed {
                        Label("The most recent task needs review.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                }
            }
        }
    }

    private func refreshActivityView(task: DriveTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Refreshing SMART data")
                        .font(.title3.weight(.semibold))
                    Text("Collecting health flags and telemetry.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Formatters.refreshTime(task.updatedAt))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ProgressView()
                .controlSize(.small)
        }
    }

    private func shouldShowActivityCard(for snapshot: DriveSnapshot) -> Bool {
        guard let task = model.currentTask(for: snapshot.id) ?? model.recentTask(for: snapshot.id) else {
            return false
        }

        switch task.kind {
        case .refresh:
            return true
        case .selfTest:
            return task.state != .running
        }
    }

    private func shouldShowSelfTestCard(for snapshot: DriveSnapshot, inspection: DeviceInspection) -> Bool {
        guard let status = inspection.selfTestStatusInfo,
              status.kind != .idle else {
            return false
        }

        guard model.shouldTreatSelfTestStatusAsLive(for: snapshot) else {
            return false
        }

        guard let task = model.currentTask(for: snapshot.id) ?? model.recentTask(for: snapshot.id) else {
            return true
        }

        switch task.kind {
        case .refresh:
            return true
        case .selfTest:
            return task.state == .running
        }
    }

    private func metricsCard(for snapshot: DriveSnapshot, inspection: DeviceInspection) -> some View {
        let liveSelfTest = model.shouldTreatSelfTestStatusAsLive(for: snapshot)
        let bridgeNote = model.bridgeReportedSelfTestNote(for: snapshot)
        let metrics = inspection.keyMetrics.filter { metric in
            liveSelfTest || metric.label != "Self-Test"
        }

        return SectionCard("What Matters") {
            VStack(alignment: .leading, spacing: 20) {
                Text(inspection.headline)
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metric.label.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .contextualHelp(TermGlossary.metric(metric.label))
                            Text(metric.value)
                                .font(.title3.weight(.semibold))
                            if let detail = metric.detail {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                if let bridgeNote {
                    Label(bridgeNote, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                if !inspection.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why")
                            .font(.headline)
                        ForEach(inspection.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func changeSummaryCard(for device: StorageDevice, inspection: DeviceInspection) -> some View {
        let changes = model.changeSummary(for: device, inspection: inspection)

        return SectionCard("What Changed") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(changes, id: \.self) { change in
                    Label(change, systemImage: change == "No meaningful change since the last check." ? "minus.circle" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }

                Text("Compared with \(model.comparisonBaseline(for: device.deviceIdentifier, currentCapturedAt: inspection.capturedAt).map { Formatters.dateTime($0.capturedAt) } ?? "the first saved check").")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func recentEventsCard(for device: StorageDevice) -> some View {
        let events = model.recentEvents(for: device.deviceIdentifier)

        if !events.isEmpty {
            SectionCard("Recent Events") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(events) { event in
                        EventRow(
                            icon: eventIcon(event),
                            color: eventColor(event),
                            eyebrow: Formatters.dateTime(event.createdAt),
                            title: event.title,
                            detail: event.detail
                        )
                    }
                }
            }
        }
    }

    private func systemContextCard(for device: StorageDevice) -> some View {
        SectionCard("Connection & macOS Context") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                contextMetric("Bus", device.busProtocol.isEmpty ? "Unavailable" : device.busProtocol)
                contextMetric("Writable", device.isWritable == nil ? "Unknown" : (device.isWritable == true ? "Yes" : "Read-only"))
                contextMetric("Mounted Volumes", "\(device.mountedPartitions.count)")
                contextMetric("Free On Mounted Volumes", Formatters.capacity(device.totalAvailableBytesOnMountedVolumes))
                contextMetric("Removable", device.isRemovable ? "Yes" : "No")
                contextMetric("Ejectable", device.isEjectable ? "Yes" : "No")
            }
        }
    }

    private func contextMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .contextualHelp(TermGlossary.context(label))
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func selfTestCard(for inspection: DeviceInspection) -> some View {
        let status = inspection.selfTestStatusInfo

        return SectionCard("Self-Test") {
            if let status {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: selfTestIcon(status))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(selfTestColor(status))
                            .frame(width: 40, height: 40)
                            .background(selfTestColor(status).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.title)
                                .font(.title3.weight(.semibold))
                            Text(status.detail)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(Formatters.refreshTime(inspection.capturedAt))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }

                    if status.isInProgress, let remaining = status.progressRemaining {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(100 - remaining), total: 100)
                                .tint(selfTestColor(status))
                            Text("About \(remaining)% remains. SmartControl will check again automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if status.kind == .passed {
                        Label("The most recent self-test finished successfully.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else if status.kind == .failed || status.kind == .aborted {
                        Label("Review this result before relying on the drive.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func selfTestIcon(_ status: SelfTestStatusInfo) -> String {
        switch status.kind {
        case .idle:
            return "minus.circle.fill"
        case .running:
            return "hourglass"
        case .passed:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .aborted:
            return "stop.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private func selfTestColor(_ status: SelfTestStatusInfo) -> Color {
        switch status.kind {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .failed:
            return .red
        case .aborted:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private func taskIcon(_ task: DriveTask) -> String {
        switch task.state {
        case .running:
            return task.kind.isSelfTest ? "hourglass" : "arrow.clockwise"
        case .waitingForAdmin:
            return "lock.fill"
        case .succeeded:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private func taskColor(_ task: DriveTask) -> Color {
        switch task.state {
        case .running:
            return task.kind.isSelfTest ? .blue : .secondary
        case .waitingForAdmin:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private func eventIcon(_ event: MonitoringEvent) -> String {
        switch event.kind {
        case .selfTestPassed:
            return "checkmark.circle"
        case .selfTestFailed:
            return "exclamationmark.triangle"
        case .healthRegressed:
            return "arrow.down.circle"
        case .alertsIncreased:
            return "bell.badge"
        case .sustainedTemperature:
            return "thermometer.medium"
        }
    }

    private func eventColor(_ event: MonitoringEvent) -> Color {
        switch event.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func recommendationIcon(_ recommendation: String) -> String {
        let lower = recommendation.lowercased()
        if lower.contains("back up") || lower.contains("replace") {
            return "exclamationmark.triangle.fill"
        }
        if lower.contains("review") || lower.contains("refresh") || lower.contains("check") {
            return "arrow.clockwise.circle"
        }
        if lower.contains("monitor") || lower.contains("watch") || lower.contains("keep an eye") {
            return "eye.circle"
        }
        if lower.contains("no immediate action") {
            return "checkmark.circle"
        }
        return "arrow.forward.circle"
    }

    private func actionCard(for snapshot: DriveSnapshot, inspection: DeviceInspection) -> some View {
        let currentTask = model.selectedSnapshot.flatMap { model.currentTask(for: $0.id) }
        let selfTestRunning = model.shouldTreatSelfTestStatusAsLive(for: snapshot) || (currentTask?.kind.isSelfTest == true && currentTask?.state == .running)
        let awaitingAdminRefresh = currentTask?.state == .waitingForAdmin
        let bridgeNote = model.bridgeReportedSelfTestNote(for: snapshot)

        return SectionCard("Actions") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.runSelfTest(.short) }
                    } label: {
                        Label("Run Short Test", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selfTestRunning)

                    Button {
                        Task { await model.runSelfTest(.extended) }
                    } label: {
                        Label("Run Extended Test", systemImage: "hourglass.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selfTestRunning)

                    Button {
                        Task { await model.refreshSelection(forcePrivilegePrompt: model.preferAdministratorAccess) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Text(selfTestRunning
                    ? "A self-test is running. SmartControl will refresh automatically and show the result here."
                    : awaitingAdminRefresh
                        ? "This drive likely needs administrator access before SmartControl can show self-test progress or results."
                        : bridgeNote != nil
                            ? "This enclosure is reporting a self-test state, but SmartControl cannot confirm that it applies to this specific drive."
                        : "Short tests are quick confidence checks. Extended tests are better before migrations, backup validation, or when a drive behaves oddly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Next Best Steps")
                    .font(.headline)

                ForEach(inspection.recommendations, id: \.self) { recommendation in
                    Label(recommendation, systemImage: recommendationIcon(recommendation))
                        .font(.body)
                }

                if !inspection.alerts.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Alerts Reported by smartctl")
                            .font(.headline)
                        ForEach(inspection.alerts, id: \.self) { message in
                            Text(message)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !inspection.technicalNotes.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Technical Notes")
                            .font(.headline)
                        ForEach(inspection.technicalNotes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func historyCard(for inspection: DeviceInspection, device: StorageDevice) -> some View {
        let previous = model.comparisonBaseline(
            for: device.deviceIdentifier,
            currentCapturedAt: inspection.capturedAt
        )
        let recent = model.recentHistory(for: device.deviceIdentifier)

        return SectionCard("Recent Checks") {
            VStack(alignment: .leading, spacing: 16) {
                if let previous {
                    historySummaryGrid(previous: previous, inspection: inspection)

                    if inspection.health == previous.health,
                       inspection.alerts.count == previous.alertsCount,
                       Formatters.signedTemperatureDelta(from: previous.temperatureC, to: inspection.summary.temperatureC) == "unchanged",
                       Formatters.signedIntDelta(from: previous.percentageUsed, to: inspection.summary.percentageUsed, suffix: "%") == "unchanged",
                       Formatters.signedIntDelta(from: previous.availableSpare, to: inspection.summary.availableSpare, suffix: "%") == "unchanged" {
                        Text("No material change since the last meaningful check.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("SmartControl is now tracking this drive. Refresh later or run a self-test to build history.")
                        .foregroundStyle(.secondary)
                }

                if !recent.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline")
                            .font(.headline)

                        ForEach(recent) { entry in
                            TimelineRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private func historySummaryGrid(previous: HistoricalDriveSnapshot, inspection: DeviceInspection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Since \(Formatters.dateTime(previous.capturedAt))")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                historyMetricTile(
                    title: "Temperature",
                    current: Formatters.temperature(inspection.summary.temperatureC),
                    change: Formatters.signedTemperatureDelta(from: previous.temperatureC, to: inspection.summary.temperatureC)
                )
                historyMetricTile(
                    title: "Endurance Used",
                    current: Formatters.percentage(inspection.summary.percentageUsed),
                    change: Formatters.signedIntDelta(from: previous.percentageUsed, to: inspection.summary.percentageUsed, suffix: "%")
                )
                historyMetricTile(
                    title: "Spare Remaining",
                    current: inspection.summary.availableSpare.map { "\($0)%" } ?? "Unavailable",
                    change: Formatters.signedIntDelta(from: previous.availableSpare, to: inspection.summary.availableSpare, suffix: "%")
                )
                historyMetricTile(
                    title: "Alerts",
                    current: "\(inspection.alerts.count)",
                    change: Formatters.signedIntDelta(from: previous.alertsCount, to: inspection.alerts.count)
                )
            }
        }
    }

    private func historyMetricTile(title: String, current: String, change: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(current)
                .font(.title3.weight(.semibold))
            if let change {
                Text(change == "unchanged" ? "No change" : change)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(change == "unchanged" ? .secondary : .tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyColor(_ health: OverallHealth) -> Color {
        switch health {
        case .healthy:
            return .green
        case .caution:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private func unavailableCard(issue: UserFacingIssue, device: StorageDevice) -> some View {
        SectionCard(issue.title) {
            VStack(alignment: .leading, spacing: 16) {
                Text(issue.message)
                    .font(.title3.weight(.semibold))

                if let suggestion = issue.recoverySuggestion {
                    MarkdownText(suggestion)
                        .foregroundStyle(.secondary)
                }

                if issue.kind == .smartctlMissing {
                    InstallCommandRow(command: "brew install smartmontools")

                    HStack(spacing: 12) {
                        Button("Check Again") {
                            Task { await model.refreshSelection() }
                        }

                        Button("Refresh All Drives") {
                            Task { await model.refresh() }
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("Export Scan Diagnostics") {
                            Task { await model.exportDiagnostics() }
                        }

                        if issue.kind == .permissionRequired {
                            Button("Refresh as Admin") {
                                Task { await model.refreshSelection(forcePrivilegePrompt: true) }
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                if let fallback = device.fallbackMetrics {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Available From Disk Utility")
                            .font(.headline)
                        Label("SMART Status: \(fallback.smartStatus ?? "Unavailable")", systemImage: "checkmark.shield")
                        Label("Temperature: \(Formatters.temperature(fallback.temperatureC))", systemImage: "thermometer")
                        Label("Power On Time: \(Formatters.powerOnTime(hours: fallback.powerOnHours))", systemImage: "clock")
                        Label("Endurance Used: \(Formatters.percentage(fallback.percentageUsed))", systemImage: "gauge.with.needle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func volumesCard(for device: StorageDevice) -> some View {
        SectionCard("Physical Layout") {
            if device.partitions.isEmpty {
                Text("No partition details were reported for this whole disk.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(device.partitions) { partition in
                        let title = partitionDisplayTitle(partition)

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.headline)
                                    .contextualHelp(TermGlossary.partition(title: title, contentType: partition.contentType))
                                Text(partitionDisplaySubtitle(partition))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Formatters.capacity(partition.sizeBytes))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func partitionDisplayTitle(_ partition: StorageDevice.Partition) -> String {
        if !partition.name.isEmpty {
            return partition.name
        }

        switch partition.contentType {
        case "Apple_APFS":
            return "APFS Container"
        case "Apple_APFS_Recovery":
            return "Recovery"
        case "Apple_APFS_ISC":
            return "System Boot Support"
        case "EFI":
            return "EFI"
        default:
            return partition.identifier
        }
    }

    private func partitionDisplaySubtitle(_ partition: StorageDevice.Partition) -> String {
        if let mountPoint = partition.mountPoint, !mountPoint.isEmpty {
            return mountPoint
        }

        if let contentType = partition.contentType, !contentType.isEmpty {
            return "\(partition.identifier) • \(humanizedContentType(contentType))"
        }

        return partition.identifier
    }

    private func humanizedContentType(_ contentType: String) -> String {
        switch contentType {
        case "Apple_APFS":
            return "APFS"
        case "Apple_APFS_Recovery":
            return "APFS Recovery"
        case "Apple_APFS_ISC":
            return "Apple Boot Support"
        case "EFI":
            return "EFI"
        default:
            return contentType.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func attributesCard(for inspection: DeviceInspection) -> some View {
        let importantAttributes = inspection.attributes.filter { !isVendorSpecificAttribute($0) }
        let vendorSpecificAttributes = inspection.attributes.filter(isVendorSpecificAttribute)

        return SectionCard("SMART Attributes") {
            VStack(alignment: .leading, spacing: 16) {
                attributeIntroGrid

                if importantAttributes.isEmpty {
                    Text("This drive mostly reports vendor-specific SMART attributes. Most users can ignore those unless they are troubleshooting with the drive vendor.")
                        .foregroundStyle(.secondary)
                } else {
                    attributeTable(attributes: importantAttributes)
                }

                if !vendorSpecificAttributes.isEmpty {
                    DisclosureGroup("Show Vendor-Specific Attributes (\(vendorSpecificAttributes.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("These raw attributes are exposed by the drive firmware, but many are not standardized or user-friendly.")
                                .foregroundStyle(.secondary)

                            attributeTable(attributes: vendorSpecificAttributes)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attributeTable(attributes: [DeviceInspection.Attribute]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            attributeTableHeader

            ForEach(Array(attributes.enumerated()), id: \.element.id) { index, attribute in
                if index > 0 {
                    Divider()
                }

                let readableName = readableAttributeName(attribute.name)
                let assessment = attributeAssessment(for: attribute, readableName: readableName)

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(readableName)
                            .font(.body.weight(.semibold))
                            .contextualHelp(TermGlossary.attribute(readableName))

                        AttributeAssessmentView(assessment: assessment)

                        if let status = attribute.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 228, alignment: .leading)

                    Text(formattedReportedValue(for: attribute, readableName: readableName))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 170, alignment: .leading)
                        .contextualHelp(TermGlossary.attribute(readableName))

                    HStack(spacing: 18) {
                        scoreCell(
                            title: "Now",
                            value: attribute.current ?? "—",
                            emphasize: assessment.emphasizeScores
                        )
                        scoreCell(
                            title: "Low",
                            value: attribute.worst ?? "—",
                            emphasize: assessment.emphasizeScores
                        )
                        scoreCell(
                            title: "Fail",
                            value: attribute.threshold ?? "—",
                            emphasize: assessment.emphasizeScores
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var attributeIntroGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            attributeIntroTile(
                title: "Read This First",
                body: "Reported Value is the literal reading. Start there."
            )
            attributeIntroTile(
                title: "About The 100s",
                body: "Health Score is a firmware scale. Repeated 100s are common and do not mean 100%."
            )
            attributeIntroTile(
                title: "Reference Rows",
                body: "Some rows are context counters, not pass-fail gauges. Hours, cycles, and LBAs live here."
            )
        }
    }

    private func attributeIntroTile(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var attributeTableHeader: some View {
        HStack(alignment: .bottom, spacing: 24) {
            Text("Attribute")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 228, alignment: .leading)
                .contextualHelp(TermGlossary.attributeColumn("Name"))

            Text("Reported Value")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)
                .contextualHelp(TermGlossary.attributeColumn("Reported Value"))

            HStack(spacing: 18) {
                Text("Health Score")
                    .frame(width: 58, alignment: .leading)
                    .contextualHelp(TermGlossary.attributeColumn("Health Score"))
                Text("Lowest Score")
                    .frame(width: 58, alignment: .leading)
                    .contextualHelp(TermGlossary.attributeColumn("Lowest Score"))
                Text("Failure Score")
                    .frame(width: 58, alignment: .leading)
                    .contextualHelp(TermGlossary.attributeColumn("Failure Score"))
            }
            .font(.headline)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
    }

    private func scoreCell(title: String, value: String, emphasize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(emphasize ? .primary : .secondary)
        }
        .frame(width: 58, alignment: .leading)
    }

    private func isVendorSpecificAttribute(_ attribute: DeviceInspection.Attribute) -> Bool {
        attribute.name.hasPrefix("Unknown")
            || attribute.name.hasSuffix("_Attribute")
            || attribute.name.contains("Unknown_")
    }

    private func readableAttributeName(_ name: String) -> String {
        switch name {
        case "Reallocated_Sector_Ct":
            return "Reallocated Sectors"
        case "Power_On_Hours":
            return "Power-On Hours"
        case "Power_Cycle_Count":
            return "Power Cycles"
        case "Reported_Uncorrect":
            return "Reported Uncorrectable Errors"
        case "Command_Timeout":
            return "Command Timeouts"
        case "Temperature_Celsius":
            return "Temperature"
        case "UDMA_CRC_Error_Count":
            return "CRC Errors"
        case "Media_Wearout_Indicator":
            return "Media Wearout Indicator"
        case "Available_Reservd_Space":
            return "Available Reserved Space"
        case "Total_LBAs_Written":
            return "Total LBAs Written"
        case "Total_LBAs_Read":
            return "Total LBAs Read"
        case "End-to-End_Error":
            return "End-to-End Errors"
        default:
            return name.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func formattedReportedValue(for attribute: DeviceInspection.Attribute, readableName: String) -> String {
        guard let raw = attribute.raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return "—"
        }

        switch readableName {
        case "Reallocated Sectors":
            return appendUnit("sectors", to: raw)
        case "Power-On Hours":
            return appendUnit("h", to: raw)
        case "Power Cycles":
            return appendUnit("cycles", to: raw)
        case "End-to-End Errors", "Reported Uncorrectable Errors", "CRC Errors":
            return appendUnit("errors", to: raw)
        case "Command Timeouts":
            return appendUnit("timeouts", to: raw)
        case "Temperature":
            return formattedTemperatureRawValue(raw)
        case "Available Reserved Space":
            return raw.hasSuffix("%") ? raw : "\(raw)%"
        case "Total LBAs Written", "Total LBAs Read":
            return appendUnit("LBAs", to: raw)
        case "Media Wearout Indicator":
            return "\(raw) vendor units"
        default:
            return raw
        }
    }

    private func appendUnit(_ unit: String, to raw: String) -> String {
        guard let value = Int(raw) else {
            return raw
        }

        return "\(value.formatted()) \(unit)"
    }

    private func formattedTemperatureRawValue(_ raw: String) -> String {
        let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard let current = digits.first else {
            return raw
        }

        if digits.count >= 3 {
            return "\(current) °C (min/max \(digits[1])/\(digits[2]) °C)"
        }

        return "\(current) °C"
    }

    private func attributeAssessment(for attribute: DeviceInspection.Attribute, readableName: String) -> AttributeAssessment {
        if let current = Int(attribute.current ?? ""),
           let threshold = Int(attribute.threshold ?? ""),
           threshold > 0,
           current <= threshold {
            return AttributeAssessment(kind: .bad, summary: "at or past the drive's failure score", emphasizeScores: true)
        }

        let rawInt = primaryInteger(from: attribute.raw)

        switch readableName {
        case "Reallocated Sectors":
            if let rawInt, rawInt > 0 {
                return AttributeAssessment(kind: .watch, summary: "should ideally stay at 0", emphasizeScores: true)
            }
            return AttributeAssessment(kind: .good, summary: "no remapped sectors reported", emphasizeScores: true)
        case "End-to-End Errors", "Reported Uncorrectable Errors", "CRC Errors":
            if let rawInt, rawInt > 0 {
                return AttributeAssessment(kind: .watch, summary: "errors should ideally stay at 0", emphasizeScores: true)
            }
            return AttributeAssessment(kind: .good, summary: "no errors reported", emphasizeScores: true)
        case "Command Timeouts":
            if let rawInt, rawInt > 0 {
                return AttributeAssessment(kind: .watch, summary: "timeouts can point to a stressed link or drive", emphasizeScores: true)
            }
            return AttributeAssessment(kind: .good, summary: "no timeouts reported", emphasizeScores: true)
        case "Temperature":
            if let temperature = primaryInteger(from: attribute.raw) {
                if temperature >= 55 {
                    return AttributeAssessment(kind: .bad, summary: "running hotter than it should", emphasizeScores: false)
                }
                if temperature >= 50 {
                    return AttributeAssessment(kind: .watch, summary: "warm, but not automatically alarming", emphasizeScores: false)
                }
                return AttributeAssessment(kind: .good, summary: "within a comfortable range", emphasizeScores: false)
            }
            return AttributeAssessment(kind: .unknown, summary: "no clear temperature reading", emphasizeScores: false)
        case "Available Reserved Space":
            if let current = Int(attribute.current ?? ""),
               let threshold = Int(attribute.threshold ?? ""),
               current > threshold {
                return AttributeAssessment(kind: .good, summary: "comfortably above the failure score", emphasizeScores: true)
            }
            if let rawInt {
                if rawInt <= 10 {
                    return AttributeAssessment(kind: .watch, summary: "spare pool is getting low", emphasizeScores: true)
                }
                return AttributeAssessment(kind: .good, summary: "plenty of spare space remains", emphasizeScores: true)
            }
            return AttributeAssessment(kind: .unknown, summary: "vendor reserve reading", emphasizeScores: true)
        case "Media Wearout Indicator":
            return AttributeAssessment(kind: .reference, summary: "vendor wear counter; compare over time", emphasizeScores: false)
        case "Power-On Hours":
            return AttributeAssessment(kind: .reference, summary: "age counter, not a failure signal by itself", emphasizeScores: false)
        case "Power Cycles":
            return AttributeAssessment(kind: .reference, summary: "lifetime power-up count", emphasizeScores: false)
        case "Total LBAs Written":
            return AttributeAssessment(kind: .reference, summary: "lifetime writes, not a score", emphasizeScores: false)
        case "Total LBAs Read":
            return AttributeAssessment(kind: .reference, summary: "lifetime reads, not a score", emphasizeScores: false)
        default:
            if let current = Int(attribute.current ?? ""),
               let threshold = Int(attribute.threshold ?? ""),
               threshold > 0 {
                if current <= threshold {
                    return AttributeAssessment(kind: .bad, summary: "at or below the drive's failure score", emphasizeScores: true)
                }
                return AttributeAssessment(kind: .good, summary: "firmware score is comfortably above failure", emphasizeScores: true)
            }
            return AttributeAssessment(kind: .reference, summary: "reported for context", emphasizeScores: false)
        }
    }
    private func primaryInteger(from raw: String?) -> Int? {
        guard let raw else {
            return nil
        }

        let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard let first = digits.first else {
            return nil
        }

        return Int(first)
    }

    private func rawOutputCard(for inspection: DeviceInspection) -> some View {
        SectionCard("Technical Details") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use this only if you want the exact smartctl command and raw JSON output.")
                    .foregroundStyle(.secondary)

                DisclosureGroup("Show Raw smartctl Output") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(inspection.commandDescription)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)

                        Text("Last refreshed at \(Formatters.refreshTime(inspection.capturedAt)) using \(inspection.smartctlPath).")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)

                        ScrollView(.horizontal) {
                            Text(inspection.rawJSON)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct MarkdownText: View {
    let string: String

    init(_ string: String) {
        self.string = string
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: string) {
            Text(attributed)
        } else {
            Text(string)
        }
    }
}

struct InstallCommandRow: View {
    let command: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            Text(command)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
                didCopy = true

                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Copy install command")
            .accessibilityLabel("Copy install command")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .contextualHelp(TermGlossary.section(title))
            }

            content
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

private struct AttributeAssessment: Hashable {
    enum Kind: Hashable {
        case good
        case watch
        case bad
        case reference
        case unknown

        var title: String {
            switch self {
            case .good:
                return "Good"
            case .watch:
                return "Watch"
            case .bad:
                return "Bad"
            case .reference:
                return "Reference"
            case .unknown:
                return "Unknown"
            }
        }

        var color: Color {
            switch self {
            case .good:
                return .green
            case .watch:
                return .orange
            case .bad:
                return .red
            case .reference:
                return .secondary
            case .unknown:
                return .secondary
            }
        }
    }

    let kind: Kind
    let summary: String
    let emphasizeScores: Bool
}

private struct AttributeAssessmentView: View {
    let assessment: AttributeAssessment

    var body: some View {
        HStack(spacing: 6) {
            Text(assessment.kind.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(assessment.kind.color.opacity(0.14), in: Capsule())
                .foregroundStyle(assessment.kind.color)

            Text(assessment.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct EventRow: View {
    let icon: String
    let color: Color
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TimelineRow: View {
    let entry: HistoricalDriveSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.dateTime(entry.capturedAt))
                    .font(.subheadline.weight(.medium))
                Text("Recorded health snapshot")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 14) {
                Text(entry.health.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: entry.health))

                if let temperature = entry.temperatureC {
                    Text("\(Int(temperature.rounded()))°C")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func color(for health: OverallHealth) -> Color {
        switch health {
        case .healthy:
            return .green
        case .caution:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
