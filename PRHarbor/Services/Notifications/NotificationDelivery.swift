import Foundation
import UserNotifications

/// Posts PR Harbor's notifications. One about a pull request carries its URL and an Open action;
/// any other opens the panel when clicked.
nonisolated struct NotificationDelivery: Sendable {
    enum Category: String, CaseIterable, Sendable { case review, assigned, created, rotting }
    static let openAction = "OPEN_PR"

    /// Asks for permission and registers the categories, so every pull request notification has an Open action.
    static func register() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let open = UNNotificationAction(identifier: openAction, title: "Open PR", options: [.foreground])
        center.setNotificationCategories(
            Set(
                Category.allCases.map {
                    UNNotificationCategory(identifier: $0.rawValue, actions: [open], intentIdentifiers: [])
                }))
    }

    var post: @Sendable (UNNotificationRequest) -> Void = { UNUserNotificationCenter.current().add($0) }

    /// Announces pull requests that appeared since the last refresh, for the kinds the settings enable.
    func announceNew(requested: [Pull], assigned: [Pull], created: [Pull], settings: PullRequestSettings) {
        let announcements: [(enabled: Bool, pulls: [Pull], title: String, category: Category)] = [
            (settings.notifyReviewRequested, requested, "Review requested", .review),
            (settings.notifyAssigned, assigned, "PR assigned to you", .assigned),
            (settings.notifyCreated, created, "New PR created", .created)
        ]
        for announcement in announcements where announcement.enabled {
            for pull in announcement.pulls { pullRequest(pull, title: announcement.title, category: announcement.category) }
        }
    }

    func pullRequest(_ pull: Pull, title: String, category: Category) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "\(pull.repository.nameWithOwner) #\(pull.number)"
        content.body = pull.title
        content.sound = .default
        content.userInfo = ["url": pull.url.absoluteString]
        content.categoryIdentifier = category.rawValue
        post(UNNotificationRequest(identifier: "pr-\(pull.url.absoluteString)", content: content, trigger: nil))
    }

    /// A notification without a pull request, such as the morning summary.
    func message(title: String, body: String, identifier: String = "timeline-morning") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        post(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
