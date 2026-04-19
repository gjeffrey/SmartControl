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

enum OverallHealth: String, Hashable {
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

enum SmartSelfTestKind: String, CaseIterable, Hashable {
    case short
    case extended

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
