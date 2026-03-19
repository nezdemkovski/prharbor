
import Foundation
import UserNotifications
import Defaults

func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    let openAction = UNNotificationAction(
        identifier: "OPEN_PR",
        title: "Open PR",
        options: [.foreground]
    )

    for categoryId in ["review", "assigned", "created"] {
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [openAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }
}

func sendPRNotifications(
    newReviewRequested: [Pull],
    newAssigned: [Pull],
    newCreated: [Pull]
) {
    if Defaults[.notifyReviewRequested] {
        for pr in newReviewRequested {
            sendPRNotification(
                title: "Review requested",
                pr: pr,
                category: "review"
            )
        }
    }

    if Defaults[.notifyAssigned] {
        for pr in newAssigned {
            sendPRNotification(
                title: "PR assigned to you",
                pr: pr,
                category: "assigned"
            )
        }
    }

    if Defaults[.notifyCreated] {
        for pr in newCreated {
            sendPRNotification(
                title: "New PR created",
                pr: pr,
                category: "created"
            )
        }
    }
}

private func sendPRNotification(title: String, pr: Pull, category: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = "\(pr.repository.name) #\(pr.number)"
    content.body = pr.title
    content.sound = .default
    content.userInfo = ["url": pr.url.absoluteString]
    content.categoryIdentifier = category

    let request = UNNotificationRequest(
        identifier: "pr-\(pr.url.absoluteString)",
        content: content,
        trigger: nil
    )

    UNUserNotificationCenter.current().add(request)
}
