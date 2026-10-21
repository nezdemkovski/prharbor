import AppKit
import Observation
import UserNotifications

/// Whether macOS lets PR Harbor show notifications, for the Notifications settings.
@MainActor @Observable
final class NotificationPermission {
    private(set) var status: UNAuthorizationStatus?

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.nezdemkovski.prharbor"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func sendTest() {
        NotificationDelivery().message(
            title: "PR Harbor notifications work",
            body: "Review requests, assignments and quiet pull requests will appear like this.",
            identifier: "timeline-test")
    }
}
