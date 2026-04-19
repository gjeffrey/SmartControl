import AppKit
import Foundation
import UserNotifications

@MainActor
struct NotificationService {
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()

        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func postNotificationIfNeeded(
        id: String,
        title: String,
        body: String
    ) async {
        guard !NSApp.isActive else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}
