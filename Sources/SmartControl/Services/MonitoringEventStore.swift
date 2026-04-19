import Foundation

struct MonitoringEventStore {
    private let retentionLimit = 40
    private let duplicateWindow: TimeInterval = 6 * 60 * 60

    func loadAll() throws -> [String: [MonitoringEvent]] {
        let url = try eventsFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: [MonitoringEvent]].self, from: data)
    }

    func record(
        _ event: MonitoringEvent,
        in events: [String: [MonitoringEvent]]
    ) throws -> [String: [MonitoringEvent]] {
        var updated = events
        var entries = updated[event.deviceIdentifier] ?? []

        if shouldStore(event, comparedTo: entries.last) {
            entries.append(event)
            if entries.count > retentionLimit {
                entries = Array(entries.suffix(retentionLimit))
            }
            updated[event.deviceIdentifier] = entries
            try saveAll(updated)
        }

        return updated
    }

    private func shouldStore(_ event: MonitoringEvent, comparedTo previous: MonitoringEvent?) -> Bool {
        guard let previous else {
            return true
        }

        if previous.kind != event.kind { return true }
        if previous.severity != event.severity { return true }
        if previous.title != event.title { return true }
        if previous.detail != event.detail { return true }

        return event.createdAt.timeIntervalSince(previous.createdAt) >= duplicateWindow
    }

    private func saveAll(_ events: [String: [MonitoringEvent]]) throws {
        let url = try eventsFileURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(events)
        try data.write(to: url, options: .atomic)
    }

    private func eventsFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupport
            .appendingPathComponent("SmartControl", isDirectory: true)
            .appendingPathComponent("events.json", isDirectory: false)
    }
}
