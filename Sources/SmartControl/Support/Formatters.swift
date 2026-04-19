import Foundation

enum Formatters {
    static func byteCountFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    static func hoursFormatter() -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }

    static func refreshTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    static func capacity(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "Unavailable"
        }

        return byteCountFormatter().string(fromByteCount: bytes)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(Int(value.rounded()))°C"
    }

    static func powerOnTime(hours: Int?) -> String {
        guard let hours else {
            return "Unavailable"
        }

        let seconds = TimeInterval(hours) * 3600
        return hoursFormatter().string(from: seconds) ?? "\(hours)h"
    }

    static func percentage(_ value: Int?, suffix: String = "%") -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value)\(suffix)"
    }

    static func refreshTime(_ date: Date) -> String {
        refreshTimeFormatter().string(from: date)
    }

    static func dateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter().string(from: date)
    }

    static func signedTemperatureDelta(from previous: Double?, to current: Double?) -> String? {
        guard let previous, let current else {
            return nil
        }

        let delta = Int(current.rounded()) - Int(previous.rounded())
        guard delta != 0 else {
            return "unchanged"
        }

        return delta > 0 ? "+\(delta)°C" : "\(delta)°C"
    }

    static func signedIntDelta(from previous: Int?, to current: Int?, suffix: String = "") -> String? {
        guard let previous, let current else {
            return nil
        }

        let delta = current - previous
        guard delta != 0 else {
            return "unchanged"
        }

        return delta > 0 ? "+\(delta)\(suffix)" : "\(delta)\(suffix)"
    }
}
