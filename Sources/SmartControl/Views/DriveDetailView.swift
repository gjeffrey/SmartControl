import AppKit
import Observation
import SwiftUI

struct DriveDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let snapshot = model.selectedSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
                    .padding(28)
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
                            Text("About \(remaining)% of the test remains. SmartControl will check again automatically.")
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
                    Text("Polling telemetry, health flags, and event state.")
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
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: eventIcon(event))
                                .foregroundStyle(eventColor(event))
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text(event.detail)
                                    .foregroundStyle(.secondary)
                                Text(Formatters.dateTime(event.createdAt))
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()
                        }
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
                            Text("About \(remaining)% of the test remains. SmartControl will check again automatically.")
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
                    ? "A self-test is currently running. SmartControl will refresh automatically and show the result here when it finishes."
                    : awaitingAdminRefresh
                        ? "This drive likely needs administrator access before SmartControl can show self-test progress or results."
                        : bridgeNote != nil
                            ? "This enclosure is reporting a self-test state, but SmartControl cannot confirm that it applies to this specific drive."
                        : "Short tests are quick confidence checks. Extended tests are better before a migration, backup validation, or when a drive starts behaving strangely.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Text("What To Do Next")
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
                    Text("Since \(Formatters.dateTime(previous.capturedAt))")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        historyChangeRow(
                            title: "Temperature",
                            current: Formatters.temperature(inspection.summary.temperatureC),
                            change: Formatters.signedTemperatureDelta(from: previous.temperatureC, to: inspection.summary.temperatureC)
                        )
                        historyChangeRow(
                            title: "Endurance Used",
                            current: Formatters.percentage(inspection.summary.percentageUsed),
                            change: Formatters.signedIntDelta(from: previous.percentageUsed, to: inspection.summary.percentageUsed, suffix: "%")
                        )
                        historyChangeRow(
                            title: "Spare Remaining",
                            current: inspection.summary.availableSpare.map { "\($0)%" } ?? "Unavailable",
                            change: Formatters.signedIntDelta(from: previous.availableSpare, to: inspection.summary.availableSpare, suffix: "%")
                        )
                        historyChangeRow(
                            title: "Alerts",
                            current: "\(inspection.alerts.count)",
                            change: Formatters.signedIntDelta(from: previous.alertsCount, to: inspection.alerts.count)
                        )
                    }

                    if inspection.health == previous.health,
                       inspection.alerts.count == previous.alertsCount,
                       Formatters.signedTemperatureDelta(from: previous.temperatureC, to: inspection.summary.temperatureC) == "unchanged",
                       Formatters.signedIntDelta(from: previous.percentageUsed, to: inspection.summary.percentageUsed, suffix: "%") == "unchanged",
                       Formatters.signedIntDelta(from: previous.availableSpare, to: inspection.summary.availableSpare, suffix: "%") == "unchanged" {
                        Text("Nothing material has changed since the last meaningful check.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("SmartControl is now tracking this drive. Refresh later or run a self-test to start building a useful history.")
                        .foregroundStyle(.secondary)
                }

                if !recent.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timeline")
                            .font(.headline)

                        ForEach(recent) { entry in
                            HStack {
                                Text(Formatters.dateTime(entry.capturedAt))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.health.title)
                                    .foregroundStyle(historyColor(entry.health))
                                if let temperature = entry.temperatureC {
                                    Text("\(Int(temperature.rounded()))°C")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private func historyChangeRow(title: String, current: String, change: String?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(current)
                .fontWeight(.semibold)
            if let change {
                Text(change)
                    .foregroundStyle(change == "unchanged" ? .secondary : .tertiary)
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
        .font(.subheadline)
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
                Text("Hover a term if it sounds like something firmware engineers named before lunch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("Name").font(.headline).contextualHelp(TermGlossary.attributeColumn("Name"))
                Text("Current").font(.headline).contextualHelp(TermGlossary.attributeColumn("Current"))
                Text("Worst").font(.headline).contextualHelp(TermGlossary.attributeColumn("Worst"))
                Text("Threshold").font(.headline).contextualHelp(TermGlossary.attributeColumn("Threshold"))
                Text("Raw").font(.headline).contextualHelp(TermGlossary.attributeColumn("Raw"))
            }

            Divider()

            ForEach(attributes) { attribute in
                GridRow(alignment: .top) {
                    let readableName = readableAttributeName(attribute.name)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(readableName)
                            .font(.body.weight(.medium))
                            .contextualHelp(TermGlossary.attribute(readableName))
                        if let status = attribute.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Text(attribute.current ?? "—")
                    Text(attribute.worst ?? "—")
                    Text(attribute.threshold ?? "—")
                    Text(attribute.raw ?? "—")
                        .font(.body.monospaced())
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .contextualHelp(TermGlossary.section(title))
            }

            content
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}
