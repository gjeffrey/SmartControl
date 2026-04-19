import Foundation

struct StorageDevice: Identifiable, Hashable {
    struct Partition: Hashable, Identifiable {
        let identifier: String
        let name: String
        let mountPoint: String?
        let sizeBytes: Int64?
        let contentType: String?

        var id: String { identifier }
    }

    struct FallbackMetrics: Hashable {
        let smartStatus: String?
        let temperatureC: Double?
        let powerOnHours: Int?
        let percentageUsed: Int?
        let availableSpare: Int?
        let mediaErrors: Int?
    }

    let deviceIdentifier: String
    let deviceNode: String
    let mediaName: String
    let busProtocol: String
    let sizeBytes: Int64
    let isInternal: Bool
    let isSolidState: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let smartStatus: String?
    let partitions: [Partition]
    let fallbackMetrics: FallbackMetrics?

    var id: String { deviceIdentifier }

    var displayName: String {
        if !mediaName.isEmpty {
            return mediaName
        }

        return deviceIdentifier.uppercased()
    }

    var subtitle: String {
        let placement = isInternal ? "Internal" : "External"
        let medium = isSolidState ? "SSD" : "Drive"
        return [placement, medium, busProtocol].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}

struct DriveSnapshot: Identifiable, Hashable {
    let device: StorageDevice
    var inspectionState: InspectionState

    var id: String { device.id }
}

enum DriveTaskKind: Hashable {
    case refresh(admin: Bool)
    case selfTest(SmartSelfTestKind)

    var title: String {
        switch self {
        case let .refresh(admin):
            return admin ? "Admin refresh" : "Refresh"
        case let .selfTest(kind):
            switch kind {
            case .short:
                return "Short self-test"
            case .extended:
                return "Extended self-test"
            }
        }
    }

    var isSelfTest: Bool {
        if case .selfTest = self {
            return true
        }
        return false
    }

    var selfTestKind: SmartSelfTestKind? {
        if case let .selfTest(kind) = self {
            return kind
        }
        return nil
    }
}

enum DriveTaskState: Hashable {
    case running
    case waitingForAdmin
    case succeeded
    case failed
}

struct DriveTask: Hashable, Identifiable {
    let deviceIdentifier: String
    let kind: DriveTaskKind
    var state: DriveTaskState
    var title: String
    var detail: String
    let startedAt: Date
    var updatedAt: Date
    var progressRemaining: Int?

    var id: String {
        "\(deviceIdentifier)-\(kind.title)-\(startedAt.timeIntervalSince1970)"
    }

    var isActive: Bool {
        state == .running || state == .waitingForAdmin
    }
}

enum DriveActivity: Hashable {
    case idle
    case refreshing
    case selfTestRunning
    case awaitingAdminRefresh

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .refreshing:
            return "Refreshing"
        case .selfTestRunning:
            return "Self-test running"
        case .awaitingAdminRefresh:
            return "Waiting for admin refresh"
        }
    }
}

enum InspectionState: Hashable {
    case loading
    case loaded(DeviceInspection)
    case unavailable(UserFacingIssue)
}

struct UserFacingIssue: Hashable, Error {
    enum Kind: Hashable {
        case smartctlMissing
        case permissionRequired
        case commandFailed
    }

    let kind: Kind
    let title: String
    let message: String
    let recoverySuggestion: String?
}

enum OverallHealth: String, Hashable, Codable {
    case healthy
    case caution
    case critical
    case unknown

    var title: String {
        switch self {
        case .healthy:
            return "Healthy"
        case .caution:
            return "Needs Attention"
        case .critical:
            return "Critical"
        case .unknown:
            return "Unknown"
        }
    }
}

struct DeviceInspection: Hashable {
    struct Summary: Hashable {
        let modelName: String
        let serialNumber: String?
        let firmwareVersion: String?
        let protocolName: String?
        let capacityBytes: Int64?
        let temperatureC: Double?
        let powerOnHours: Int?
        let percentageUsed: Int?
        let availableSpare: Int?
        let smartPassed: Bool?
        let selfTestStatus: String?
        let dataReadBytes: Int64?
        let dataWrittenBytes: Int64?
    }

    struct KeyMetric: Hashable, Identifiable {
        let label: String
        let value: String
        let detail: String?

        var id: String { label }
    }

    struct Attribute: Hashable, Identifiable {
        let id: String
        let name: String
        let current: String?
        let worst: String?
        let threshold: String?
        let raw: String?
        let status: String?
    }

    let commandDescription: String
    let smartctlPath: String
    let capturedAt: Date
    let health: OverallHealth
    let headline: String
    let reasons: [String]
    let recommendations: [String]
    let alerts: [String]
    let technicalNotes: [String]
    let messages: [String]
    let summary: Summary
    let keyMetrics: [KeyMetric]
    let attributes: [Attribute]
    let rawJSON: String
}

struct SelfTestStatusInfo: Hashable {
    enum Kind: Hashable {
        case running
        case passed
        case failed
        case aborted
        case unknown
    }

    let kind: Kind
    let title: String
    let detail: String
    let progressRemaining: Int?

    var isInProgress: Bool {
        kind == .running
    }

    var isFinished: Bool {
        !isInProgress
    }
}

extension DeviceInspection {
    var selfTestStatusInfo: SelfTestStatusInfo? {
        SelfTestStatusInfo(rawStatus: summary.selfTestStatus)
    }
}

extension SelfTestStatusInfo {
    init?(rawStatus: String?) {
        guard let rawStatus, !rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lower = rawStatus.lowercased()
        let progressRemaining = Self.extractPercentage(from: lower)

        if lower.contains("in progress") || lower.contains("remaining") {
            self.init(
                kind: .running,
                title: "Self-test in progress",
                detail: rawStatus,
                progressRemaining: progressRemaining
            )
        } else if lower.contains("completed without error") || lower.contains("completed successfully") {
            self.init(
                kind: .passed,
                title: "Self-test completed",
                detail: rawStatus,
                progressRemaining: nil
            )
        } else if lower.contains("aborted") || lower.contains("interrupted") {
            self.init(
                kind: .aborted,
                title: "Self-test stopped",
                detail: rawStatus,
                progressRemaining: nil
            )
        } else if lower.contains("failed") || lower.contains("error") || lower.contains("read failure") {
            self.init(
                kind: .failed,
                title: "Self-test reported a problem",
                detail: rawStatus,
                progressRemaining: nil
            )
        } else {
            self.init(
                kind: .unknown,
                title: "Self-test status",
                detail: rawStatus,
                progressRemaining: progressRemaining
            )
        }
    }

    private static func extractPercentage(from string: String) -> Int? {
        guard let range = string.range(of: #"\d+(?=% remaining)"#, options: .regularExpression) else {
            return nil
        }

        return Int(string[range])
    }
}

struct SelfTestLaunchInfo: Hashable {
    let userMessage: String
}

struct HistoricalDriveSnapshot: Codable, Hashable, Identifiable {
    let deviceIdentifier: String
    let capturedAt: Date
    let health: OverallHealth
    let temperatureC: Double?
    let powerOnHours: Int?
    let percentageUsed: Int?
    let availableSpare: Int?
    let selfTestStatus: String?
    let alertsCount: Int

    var id: String {
        "\(deviceIdentifier)-\(capturedAt.timeIntervalSince1970)"
    }
}

enum MonitoringEventSeverity: String, Codable, Hashable {
    case info
    case warning
    case critical

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }
}

enum MonitoringEventKind: String, Codable, Hashable {
    case selfTestPassed
    case selfTestFailed
    case healthRegressed
    case alertsIncreased
    case sustainedTemperature
}

struct MonitoringEvent: Codable, Hashable, Identifiable {
    let deviceIdentifier: String
    let kind: MonitoringEventKind
    let severity: MonitoringEventSeverity
    let title: String
    let detail: String
    let createdAt: Date

    var id: String {
        "\(deviceIdentifier)-\(kind.rawValue)-\(createdAt.timeIntervalSince1970)"
    }
}

enum MonitoringCadence: Int, CaseIterable, Hashable, Identifiable {
    case off = 0
    case every30Minutes = 30
    case everyHour = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .every30Minutes:
            return "Every 30 Minutes"
        case .everyHour:
            return "Every Hour"
        }
    }

    var interval: Duration? {
        switch self {
        case .off:
            return nil
        case .every30Minutes:
            return .seconds(30 * 60)
        case .everyHour:
            return .seconds(60 * 60)
        }
    }
}

enum SmartSelfTestKind: String, CaseIterable, Hashable {
    case short
    case extended

    var title: String {
        switch self {
        case .short:
            return "Short self-test"
        case .extended:
            return "Extended self-test"
        }
    }

    var smartctlArgument: String {
        switch self {
        case .short:
            return "short"
        case .extended:
            return "long"
        }
    }

    var buttonTitle: String {
        switch self {
        case .short:
            return "Run Short Test"
        case .extended:
            return "Run Extended Test"
        }
    }
}
