import AppKit
import Foundation

@MainActor
struct DiagnosticsExportService {
    func exportReport(
        payload: [String: Any],
        suggestedName: String
    ) async throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }
}
