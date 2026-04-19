import Foundation

struct SmartctlService {
    private let runner = CommandRunner()
    private let batchBeginMarker = "__SMARTCONTROL_BEGIN__"
    private let batchEndMarker = "__SMARTCONTROL_END__"
    private let candidatePaths = [
        "/opt/homebrew/sbin/smartctl",
        "/usr/local/sbin/smartctl",
        "/opt/homebrew/bin/smartctl",
        "/usr/local/bin/smartctl",
        "/usr/bin/smartctl",
    ]

    func inspect(
        device: StorageDevice,
        preferredPath: String,
        useAdministratorPrompt: Bool
    ) async throws -> InspectionState {
        guard let executable = resolvedSmartctlPath(preferredPath: preferredPath) else {
            return .unavailable(
                UserFacingIssue(
                    kind: .smartctlMissing,
                    title: "smartctl Not Found",
                    message: "SmartControl could not find the smartctl executable on this Mac.",
                    recoverySuggestion: "Recommended: install smartmontools with [Homebrew](https://brew.sh) using `brew install smartmontools`, then reopen SmartControl. If you installed it elsewhere, set the path manually in Settings."
                )
            )
        }

        let arguments = ["--all", "--json", device.deviceNode]
        let command = ([executable] + arguments).joined(separator: " ")
        let result = try await runner.run(
            executable: executable,
            arguments: arguments,
            privilegeMode: useAdministratorPrompt
                ? .administratorPrompt(prompt: "SmartControl needs administrator access to read detailed SMART data for \(device.displayName).")
                : .standard
        )

        let combinedOutput = [result.stdout, result.stderr].joined(separator: "\n")
        return inspectionState(
            for: device,
            executable: executable,
            commandDescription: command,
            output: result.stdout.isEmpty ? result.stderr : result.stdout,
            combinedOutput: combinedOutput
        )
    }

    func inspectManyWithAdministratorPrompt(
        devices: [StorageDevice],
        preferredPath: String
    ) async throws -> [String: InspectionState] {
        guard let executable = resolvedSmartctlPath(preferredPath: preferredPath) else {
            let issue = UserFacingIssue(
                kind: .smartctlMissing,
                title: "smartctl Not Found",
                message: "SmartControl could not find the smartctl executable on this Mac.",
                recoverySuggestion: "Recommended: install smartmontools with [Homebrew](https://brew.sh) using `brew install smartmontools`, then reopen SmartControl. If you installed it elsewhere, set the path manually in Settings."
            )
            return Dictionary(uniqueKeysWithValues: devices.map { ($0.id, .unavailable(issue)) })
        }

        let command = devices.map { device in
            let escapedNode = shellEscape(device.deviceNode)
            let escapedExecutable = shellEscape(executable)
            return """
            printf '%s%s\\n' '\(batchBeginMarker)' \(escapedNode)
            \(escapedExecutable) --all --json \(escapedNode) 2>&1 || true
            printf '\\n%s%s\\n' '\(batchEndMarker)' \(escapedNode)
            """
        }.joined(separator: "\n")

        let result = try await runner.runShell(
            command,
            privilegeMode: .administratorPrompt(prompt: "SmartControl needs administrator access to refresh SMART data for your connected drives.")
        )
        let segments = parseBatchOutput(result.stdout)

        var states: [String: InspectionState] = [:]
        for device in devices {
            let commandDescription = ([executable, "--all", "--json", device.deviceNode]).joined(separator: " ")
            if let output = segments[device.deviceNode] {
                states[device.id] = inspectionState(
                    for: device,
                    executable: executable,
                    commandDescription: commandDescription,
                    output: output,
                    combinedOutput: output
                )
            } else {
                states[device.id] = .unavailable(
                    UserFacingIssue(
                        kind: .commandFailed,
                        title: "SMART Read Failed",
                        message: "SmartControl did not receive a response for \(device.displayName).",
                        recoverySuggestion: "Try again with administrator access."
                    )
                )
            }
        }

        return states
    }

    func runSelfTest(
        on device: StorageDevice,
        kind: SmartSelfTestKind,
        preferredPath: String,
        useAdministratorPrompt: Bool
    ) async throws -> Result<SelfTestLaunchInfo, UserFacingIssue> {
        guard let executable = resolvedSmartctlPath(preferredPath: preferredPath) else {
            return .failure(
                UserFacingIssue(
                    kind: .smartctlMissing,
                    title: "smartctl Not Found",
                    message: "SmartControl could not find smartctl, so it cannot start a self-test.",
                    recoverySuggestion: "Recommended: install smartmontools with [Homebrew](https://brew.sh) using `brew install smartmontools`, then reopen SmartControl. If you installed it elsewhere, set the path manually in Settings."
                )
            )
        }

        let result = try await runner.run(
            executable: executable,
            arguments: ["-t", kind.smartctlArgument, device.deviceNode],
            privilegeMode: useAdministratorPrompt
                ? .administratorPrompt(prompt: "SmartControl needs administrator access to start a SMART self-test on \(device.displayName).")
                : .standard
        )
        let combined = [result.stdout, result.stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isPermissionIssue(combined) {
            return .failure(
                UserFacingIssue(
                    kind: .permissionRequired,
                    title: "Administrator Access Needed",
                    message: "smartctl needs administrator access to start a self-test on \(device.displayName).",
                    recoverySuggestion: "Retry with administrator access enabled."
                )
            )
        }

        if result.exitCode != 0 && combined.isEmpty {
            return .failure(
                UserFacingIssue(
                    kind: .commandFailed,
                    title: "Self-Test Failed to Start",
                    message: "smartctl exited with status \(result.exitCode).",
                    recoverySuggestion: "Try again with administrator access."
                )
            )
        }

        return .success(SelfTestLaunchInfo(userMessage: summarizeSelfTestLaunch(kind: kind, output: combined, device: device)))
    }

    private func resolvedSmartctlPath(preferredPath: String) -> String? {
        let trimmed = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }

        return candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func inspectionState(
        for device: StorageDevice,
        executable: String,
        commandDescription: String,
        output: String,
        combinedOutput: String
    ) -> InspectionState {
        guard let data = output.data(using: .utf8), let root = try? JSONValue.decode(data: data) else {
            if isPermissionIssue(combinedOutput) {
                return .unavailable(
                    UserFacingIssue(
                        kind: .permissionRequired,
                        title: "Administrator Access Needed",
                        message: "smartctl could not read \(device.displayName) without elevated privileges.",
                        recoverySuggestion: "Use “Refresh as Admin” or turn on administrator access in Settings."
                    )
                )
            }

            return .unavailable(
                UserFacingIssue(
                    kind: .commandFailed,
                    title: "SMART Read Failed",
                    message: combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "smartctl did not return usable data for this disk." : combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                    recoverySuggestion: "Check the selected smartctl path, then try again with administrator access."
                )
            )
        }

        let inspection = makeInspection(
            root: root,
            rawJSON: output,
            device: device,
            commandDescription: commandDescription,
            smartctlPath: executable
        )

        return .loaded(inspection)
    }

    private func makeInspection(
        root: JSONValue,
        rawJSON: String,
        device: StorageDevice,
        commandDescription: String,
        smartctlPath: String
    ) -> DeviceInspection {
        let modelName = firstString(
            root,
            paths: [
                ["model_name"],
                ["product"],
                ["device", "name"],
            ]
        ) ?? device.displayName
        let serialNumber = firstString(root, paths: [["serial_number"]])
        let firmwareVersion = firstString(root, paths: [["firmware_version"]])
        let protocolName = firstString(root, paths: [["device", "protocol"], ["device", "type"]]) ?? device.busProtocol
        let capacityBytes = firstInt64(root, paths: [["user_capacity", "bytes"]]) ?? device.sizeBytes
        let smartPassed = firstBool(root, paths: [["smart_status", "passed"]])
        let temperatureC = firstTemperature(root: root) ?? device.fallbackMetrics?.temperatureC
        let powerOnHours = firstInt(root, paths: [["power_on_time", "hours"], ["power_on_time", "hours_value"]]) ?? device.fallbackMetrics?.powerOnHours
        let percentageUsed = firstInt(root, paths: [["percentage_used"], ["nvme_smart_health_information_log", "percentage_used"]]) ?? device.fallbackMetrics?.percentageUsed
        let availableSpare = firstInt(root, paths: [["nvme_smart_health_information_log", "available_spare"]]) ?? device.fallbackMetrics?.availableSpare
        let dataReadBytes = firstDataBytes(root: root, primaryPath: ["nvme_smart_health_information_log", "data_units_read", "bytes"])
        let dataWrittenBytes = firstDataBytes(root: root, primaryPath: ["nvme_smart_health_information_log", "data_units_written", "bytes"])
        let selfTestStatus = firstString(
            root,
            paths: [
                ["ata_smart_data", "self_test", "status", "string"],
                ["scsi_self_test_0", "string"],
                ["nvme_self_test_log", "current_self_test_operation", "string"],
            ]
        )

        let messages = collectMessages(from: root)
        let attributes = buildAttributes(from: root)
        let messageInterpretation = interpret(messages: messages)
        let assessment = assessHealth(
            smartPassed: smartPassed,
            temperatureC: temperatureC,
            percentageUsed: percentageUsed,
            availableSpare: availableSpare,
            alerts: messageInterpretation.alerts,
            technicalNotes: messageInterpretation.technicalNotes,
            device: device
        )

        let summary = DeviceInspection.Summary(
            modelName: modelName,
            serialNumber: serialNumber,
            firmwareVersion: firmwareVersion,
            protocolName: protocolName,
            capacityBytes: capacityBytes,
            temperatureC: temperatureC,
            powerOnHours: powerOnHours,
            percentageUsed: percentageUsed,
            availableSpare: availableSpare,
            smartPassed: smartPassed,
            selfTestStatus: selfTestStatus,
            dataReadBytes: dataReadBytes,
            dataWrittenBytes: dataWrittenBytes
        )

        let keyMetrics = buildMetrics(
            summary: summary,
            alerts: messageInterpretation.alerts,
            technicalNotes: messageInterpretation.technicalNotes
        )

        return DeviceInspection(
            commandDescription: commandDescription,
            smartctlPath: smartctlPath,
            capturedAt: Date(),
            health: assessment.health,
            headline: assessment.headline,
            reasons: assessment.reasons,
            recommendations: assessment.recommendations,
            alerts: messageInterpretation.alerts,
            technicalNotes: messageInterpretation.technicalNotes,
            messages: messages,
            summary: summary,
            keyMetrics: keyMetrics,
            attributes: attributes,
            rawJSON: rawJSON
        )
    }

    private func buildMetrics(
        summary: DeviceInspection.Summary,
        alerts: [String],
        technicalNotes: [String]
    ) -> [DeviceInspection.KeyMetric] {
        var metrics: [DeviceInspection.KeyMetric] = [
            .init(label: "Capacity", value: Formatters.capacity(summary.capacityBytes), detail: nil),
            .init(label: "Temperature", value: Formatters.temperature(summary.temperatureC), detail: summary.temperatureC == nil ? "No live temperature reading" : nil),
            .init(label: "Power On", value: Formatters.powerOnTime(hours: summary.powerOnHours), detail: nil),
            .init(label: "Endurance Used", value: Formatters.percentage(summary.percentageUsed), detail: summary.percentageUsed == nil ? "Not reported" : nil),
        ]

        if let availableSpare = summary.availableSpare {
            metrics.append(.init(label: "Spare Remaining", value: "\(availableSpare)%", detail: nil))
        }

        if let read = summary.dataReadBytes {
            metrics.append(.init(label: "Data Read", value: Formatters.capacity(read), detail: nil))
        }

        if let written = summary.dataWrittenBytes {
            metrics.append(.init(label: "Data Written", value: Formatters.capacity(written), detail: nil))
        }

        if let selfTestStatus = summary.selfTestStatus {
            metrics.append(.init(label: "Self-Test", value: selfTestStatus, detail: nil))
        }

        if !alerts.isEmpty {
            metrics.append(.init(label: "Alerts", value: "\(alerts.count)", detail: "Needs review"))
        } else if !technicalNotes.isEmpty {
            metrics.append(.init(label: "Notes", value: "\(technicalNotes.count)", detail: "Technical detail only"))
        }

        return metrics
    }

    private func buildAttributes(from root: JSONValue) -> [DeviceInspection.Attribute] {
        guard let table = root.value(at: ["ata_smart_attributes", "table"])?.arrayValue else {
            return []
        }

        return table.compactMap { row in
            let id = row["id"]?.stringValue ?? UUID().uuidString
            let name = row["name"]?.stringValue ?? "Attribute"
            let rawValue = row.value(at: ["raw", "string"])?.stringValue ?? row.value(at: ["raw", "value"])?.stringValue
            let whenFailed = row["when_failed"]?.stringValue
            let threshold = row["thresh"]?.stringValue
            let current = row["value"]?.stringValue
            let worst = row["worst"]?.stringValue

            return DeviceInspection.Attribute(
                id: id,
                name: name,
                current: current,
                worst: worst,
                threshold: threshold,
                raw: rawValue,
                status: whenFailed == "-" ? nil : whenFailed
            )
        }
    }

    private func assessHealth(
        smartPassed: Bool?,
        temperatureC: Double?,
        percentageUsed: Int?,
        availableSpare: Int?,
        alerts: [String],
        technicalNotes: [String],
        device: StorageDevice
    ) -> (health: OverallHealth, headline: String, reasons: [String], recommendations: [String]) {
        var reasons: [String] = []
        var recommendations: [String] = []
        var health: OverallHealth = .healthy

        if let smartPassed, smartPassed == false {
            health = .critical
            reasons.append("SMART has already flagged this disk as failed.")
            recommendations.append("Back up the disk immediately and plan a replacement.")
        }

        if let temperatureC, temperatureC >= 60 {
            health = .critical
            reasons.append("Drive temperature is critically high at \(Int(temperatureC.rounded()))°C.")
            recommendations.append("Reduce sustained load and check airflow or enclosure cooling.")
        } else if let temperatureC, temperatureC >= 50 {
            health = maxHealth(health, .caution)
            reasons.append("Drive temperature is elevated at \(Int(temperatureC.rounded()))°C.")
            recommendations.append("Keep an eye on temperature during long writes and tests.")
        }

        if let percentageUsed, percentageUsed >= 100 {
            health = .critical
            reasons.append("Reported endurance is fully consumed.")
            recommendations.append("Replace this SSD as soon as possible.")
        } else if let percentageUsed, percentageUsed >= 80 {
            health = maxHealth(health, .caution)
            reasons.append("This SSD has used \(percentageUsed)% of its rated endurance.")
            recommendations.append("Schedule replacement planning before failures start stacking up.")
        }

        if let availableSpare, availableSpare <= 10 {
            health = .critical
            reasons.append("Only \(availableSpare)% spare capacity remains.")
            recommendations.append("Replace the drive and confirm backups are current.")
        } else if let availableSpare, availableSpare <= 20 {
            health = maxHealth(health, .caution)
            reasons.append("Available spare has dropped to \(availableSpare)%.")
            recommendations.append("Monitor spare capacity and run a short self-test.")
        }

        if !alerts.isEmpty {
            health = maxHealth(health, .caution)
            reasons.append("smartctl reported issues that deserve a closer look.")
            recommendations.append("Review the reported alerts below before making changes or replacements.")
        }

        if reasons.isEmpty {
            if let smartPassed, smartPassed {
                reasons.append("SMART currently reports this disk as passing.")
            } else if let status = device.smartStatus {
                reasons.append("Disk Utility reports SMART status as \(status.lowercased()).")
            } else {
                reasons.append("No immediate SMART problems were detected from the available data.")
            }

            if !technicalNotes.isEmpty {
                reasons.append("A few advanced SMART details could not be read, but that does not usually indicate drive failure.")
            }

            recommendations.append("No immediate action is needed.")
            recommendations.append("Refresh after heavy workloads or before maintenance windows.")
        }

        let headline: String
        switch health {
        case .healthy:
            headline = technicalNotes.isEmpty
                ? "This drive looks healthy right now."
                : "This drive looks healthy. Some advanced diagnostics were simply unavailable."
        case .caution:
            headline = "This drive is still usable, but it needs attention."
        case .critical:
            headline = "This drive is at risk and should be treated as urgent."
        case .unknown:
            headline = "Health could not be determined confidently."
        }

        return (health, headline, reasons, Array(NSOrderedSet(array: recommendations)) as? [String] ?? recommendations)
    }

    private func maxHealth(_ lhs: OverallHealth, _ rhs: OverallHealth) -> OverallHealth {
        let order: [OverallHealth: Int] = [.healthy: 0, .unknown: 1, .caution: 2, .critical: 3]
        return (order[lhs] ?? 0) >= (order[rhs] ?? 0) ? lhs : rhs
    }

    private func firstString(_ root: JSONValue, paths: [[String]]) -> String? {
        for path in paths {
            if let value = root.value(at: path)?.stringValue, !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func firstInt(_ root: JSONValue, paths: [[String]]) -> Int? {
        for path in paths {
            if let value = root.value(at: path)?.intValue {
                return value
            }
        }

        return nil
    }

    private func firstInt64(_ root: JSONValue, paths: [[String]]) -> Int64? {
        for path in paths {
            if let value = root.value(at: path)?.doubleValue {
                return Int64(value)
            }
        }

        return nil
    }

    private func firstBool(_ root: JSONValue, paths: [[String]]) -> Bool? {
        for path in paths {
            if let value = root.value(at: path)?.boolValue {
                return value
            }
        }

        return nil
    }

    private func firstTemperature(root: JSONValue) -> Double? {
        if let current = root.value(at: ["temperature", "current"])?.doubleValue {
            return current
        }

        if let nvme = root.value(at: ["nvme_smart_health_information_log", "temperature"])?.doubleValue {
            return nvme > 200 ? nvme - 273 : nvme
        }

        return nil
    }

    private func firstDataBytes(root: JSONValue, primaryPath: [String]) -> Int64? {
        if let bytes = root.value(at: primaryPath)?.doubleValue {
            return Int64(bytes)
        }

        return nil
    }

    private func collectMessages(from root: JSONValue) -> [String] {
        let entries = root.value(at: ["smartctl", "messages"])?.arrayValue ?? []
        let strings = entries.compactMap { entry -> String? in
            if let text = entry["string"]?.stringValue {
                return text
            }

            return entry.stringValue
        }

        return strings.filter { !$0.isEmpty }
    }

    private func interpret(messages: [String]) -> (alerts: [String], technicalNotes: [String]) {
        var alerts: [String] = []
        var technicalNotes: [String] = []

        for message in messages {
            let lowered = message.lowercased()

            if lowered.contains("getlogpage failed") || lowered.contains("error information log failed") {
                technicalNotes.append("smartctl could not read one optional NVMe error-information log on this Mac. The drive still reports SMART as passing, so this is usually a tool or firmware limitation rather than a health problem.")
            } else if lowered.contains("unsupported") || lowered.contains("not supported") || lowered.contains("not implemented") {
                technicalNotes.append("Some optional SMART details are not available for this drive or enclosure.")
            } else if lowered.contains("error") || lowered.contains("failed") {
                alerts.append(message)
            } else {
                technicalNotes.append(message)
            }
        }

        let uniqueAlerts = Array(NSOrderedSet(array: alerts)) as? [String] ?? alerts
        let uniqueNotes = Array(NSOrderedSet(array: technicalNotes)) as? [String] ?? technicalNotes
        return (uniqueAlerts, uniqueNotes)
    }

    private func isPermissionIssue(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
            || lowered.contains("must be root")
            || lowered.contains("admin")
    }

    private func summarizeSelfTestLaunch(
        kind: SmartSelfTestKind,
        output: String,
        device: StorageDevice
    ) -> String {
        let waitMinutes = extractWaitMinutes(from: output)
        let prefix = kind == .short ? "Short self-test started for \(device.displayName)." : "Extended self-test started for \(device.displayName)."
        let adminHint = device.isInternal ? " Use Refresh as Admin later to check progress on this drive." : ""

        if let waitMinutes {
            return "\(prefix) Expected time: about \(waitMinutes) minute\(waitMinutes == 1 ? "" : "s").\(adminHint)"
        }

        if output.lowercased().contains("testing has begun") {
            return "\(prefix) SmartControl will keep checking until the result is available.\(adminHint)"
        }

        return "\(prefix)\(adminHint)"
    }

    private func extractWaitMinutes(from string: String) -> Int? {
        guard let range = string.range(of: #"please wait\s+(\d+)\s+minutes?"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let substring = String(string[range])
        guard let minuteRange = substring.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }

        return Int(substring[minuteRange])
    }

    private func parseBatchOutput(_ output: String) -> [String: String] {
        var segments: [String: String] = [:]
        var currentDeviceNode: String?
        var currentLines: [String] = []

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix(batchBeginMarker) {
                currentDeviceNode = String(line.dropFirst(batchBeginMarker.count))
                currentLines = []
                continue
            }

            if line.hasPrefix(batchEndMarker) {
                let deviceNode = String(line.dropFirst(batchEndMarker.count))
                if let currentDeviceNode, deviceNode == currentDeviceNode {
                    segments[deviceNode] = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentDeviceNode = nil
                currentLines = []
                continue
            }

            if currentDeviceNode != nil {
                currentLines.append(line)
            }
        }

        return segments
    }

    private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
