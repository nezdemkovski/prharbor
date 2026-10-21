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
        sendTimelineNotification(title: "PR Harbor notifications work",
                                 body: "Review requests, assignments and quiet pull requests will appear like this.",
                                 identifier: "timeline-test")
    }
}

func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

    let openAction = UNNotificationAction(
        identifier: "OPEN_PR",
        title: "Open PR",
        options: [.foreground]
    )

    let categories: Set<UNNotificationCategory> = Set(
        ["review", "assigned", "created", "rotting"].map { categoryId in
            UNNotificationCategory(
                identifier: categoryId,
                actions: [openAction],
                intentIdentifiers: []
            )
        }
    )
    center.setNotificationCategories(categories)
}
