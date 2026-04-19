import Foundation

struct InspectionHistoryStore {
    private let retentionLimit = 50
    private let minimumRefreshIntervalToAlwaysStore: TimeInterval = 6 * 60 * 60

    func loadAll() throws -> [String: [HistoricalDriveSnapshot]] {
        let url = try historyFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: [HistoricalDriveSnapshot]].self, from: data)
    }

    func record(
        _ snapshot: HistoricalDriveSnapshot,
        in history: [String: [HistoricalDriveSnapshot]]
    ) throws -> [String: [HistoricalDriveSnapshot]] {
        var updated = history
        var entries = updated[snapshot.deviceIdentifier] ?? []

        if shouldStore(snapshot, comparedTo: entries.last) {
            entries.append(snapshot)
            if entries.count > retentionLimit {
                entries = Array(entries.suffix(retentionLimit))
            }
            updated[snapshot.deviceIdentifier] = entries
            try saveAll(updated)
        }

        return updated
    }

    private func shouldStore(
        _ snapshot: HistoricalDriveSnapshot,
        comparedTo previous: HistoricalDriveSnapshot?
    ) -> Bool {
        guard let previous else {
            return true
        }

        if snapshot.health != previous.health { return true }
        if snapshot.temperatureC.map(Int.init) != previous.temperatureC.map(Int.init) { return true }
        if snapshot.powerOnHours != previous.powerOnHours { return true }
        if snapshot.percentageUsed != previous.percentageUsed { return true }
        if snapshot.availableSpare != previous.availableSpare { return true }
        if snapshot.selfTestStatus != previous.selfTestStatus { return true }
        if snapshot.alertsCount != previous.alertsCount { return true }

        return snapshot.capturedAt.timeIntervalSince(previous.capturedAt) >= minimumRefreshIntervalToAlwaysStore
    }

    private func saveAll(_ history: [String: [HistoricalDriveSnapshot]]) throws {
        let url = try historyFileURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }

    private func historyFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupport
            .appendingPathComponent("SmartControl", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
