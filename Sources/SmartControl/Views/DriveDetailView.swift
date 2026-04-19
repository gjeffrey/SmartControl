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

                        switch snapshot.inspectionState {
                        case .loading:
                            SectionCard("Reading SMART Data") {
                                ProgressView("Collecting structured health data…")
                                    .controlSize(.large)
                            }
                        case let .loaded(inspection):
                            metricsCard(for: inspection)
                            recommendationCard(for: inspection)
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

                if let message = model.lastActionMessage {
                    Label(message, systemImage: "sparkle")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if let error = model.lastRefreshError {
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

    private func metricsCard(for inspection: DeviceInspection) -> some View {
        SectionCard("What Matters") {
            VStack(alignment: .leading, spacing: 20) {
                Text(inspection.headline)
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    ForEach(inspection.keyMetrics) { metric in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metric.label.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
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

    private func recommendationCard(for inspection: DeviceInspection) -> some View {
        SectionCard("Actions") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(inspection.recommendations, id: \.self) { recommendation in
                    Label(recommendation, systemImage: "arrow.forward.circle")
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
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(partitionDisplayTitle(partition))
                                    .font(.headline)
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
                Text("Name").font(.headline)
                Text("Current").font(.headline)
                Text("Worst").font(.headline)
                Text("Threshold").font(.headline)
                Text("Raw").font(.headline)
            }

            Divider()

            ForEach(attributes) { attribute in
                GridRow(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(readableAttributeName(attribute.name))
                            .font(.body.weight(.medium))
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
