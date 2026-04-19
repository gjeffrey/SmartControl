import AppKit
import Foundation
import UserNotifications

enum NotificationAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case unknown
}

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

    func authorizationStatus() async -> NotificationAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .provisional:
            return .provisional
        default:
            return .unknown
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

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
