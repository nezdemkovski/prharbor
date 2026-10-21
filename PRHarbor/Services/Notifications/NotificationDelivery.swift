import Foundation
import UserNotifications

func sendPRNotifications(
    newReviewRequested: [Pull],
    newAssigned: [Pull],
    newCreated: [Pull],
    settings: PullRequestSettings
) {
    if settings.notifyReviewRequested {
        for pr in newReviewRequested {
            sendPRNotification(
                title: "Review requested",
                pr: pr,
                category: "review"
            )
        }
    }

    if settings.notifyAssigned {
        for pr in newAssigned {
            sendPRNotification(
                title: "PR assigned to you",
                pr: pr,
                category: "assigned"
            )
        }
    }

    if settings.notifyCreated {
        for pr in newCreated {
            sendPRNotification(
                title: "New PR created",
                pr: pr,
                category: "created"
            )
        }
    }
}

func sendPRNotification(title: String, pr: Pull, category: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = "\(pr.repository.nameWithOwner) #\(pr.number)"
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

/// Notifications without a pull request open the panel when clicked.
func sendTimelineNotification(title: String, body: String, identifier: String = "timeline-morning") {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
}
