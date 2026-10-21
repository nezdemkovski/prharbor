
import AppKit
import Defaults
import Foundation
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

nonisolated struct PullRefreshTracker: Sendable {
    private var knownURLs: Set<String> = []
    private var wasFetched = false

    mutating func update(edges: [Edge], fetched: Bool, canNotify: Bool) -> [Pull] {
        let newPulls: [Pull]
        if canNotify && fetched && wasFetched {
            newPulls = edges
                .filter { !knownURLs.contains($0.node.url.absoluteString) }
                .map(\.node)
        } else {
            newPulls = []
        }

        if fetched {
            knownURLs = Set(edges.map { $0.node.url.absoluteString })
        }
        wasFetched = fetched
        return newPulls
    }

    mutating func reset() {
        knownURLs = []
        wasFetched = false
    }
}

/// Decides what a completed refresh announces: newly listed PRs, PRs that went quiet,
/// and the morning summary. Restored cache and the first fetch never notify.
@MainActor
final class PullNotificationCoordinator {
    private var reviewRequested = PullRefreshTracker()
    private var assigned = PullRefreshTracker()
    private var created = PullRefreshTracker()
    private var hasLoadedOnce = false
    private var knownRotting: Set<String>?
    private var previousThresholds: [Int]?

    /// Returns the day of a morning summary it sent, for the caller to remember.
    @discardableResult
    func refreshed(assigned: [Edge], created: [Edge], requested: [Edge], fetched: PullSources,
                   items: [TimelineItem], settings: PullRequestSettings) -> String? {
        let newRequested = reviewRequested.update(edges: requested, fetched: fetched.contains(.requested), canNotify: hasLoadedOnce)
        let newAssigned = self.assigned.update(edges: assigned, fetched: fetched.contains(.assigned), canNotify: hasLoadedOnce)
        let newCreated = self.created.update(edges: created, fetched: fetched.contains(.created), canNotify: hasLoadedOnce)
        if hasLoadedOnce {
            sendPRNotifications(newReviewRequested: newRequested, newAssigned: newAssigned, newCreated: newCreated, settings: settings)
        }
        hasLoadedOnce = true
        return summarize(items, settings: settings)
    }

    func reset() {
        reviewRequested.reset()
        assigned.reset()
        created.reset()
        hasLoadedOnce = false
        knownRotting = nil
        previousThresholds = nil
    }

    private func summarize(_ items: [TimelineItem], settings: PullRequestSettings) -> String? {
        let rotting = TimelineNotificationPolicy.rottingOwned(items)
        let thresholds = settings.thresholds
        if settings.notifyRotting {
            for item in TimelineNotificationPolicy.newlyRotting(rotting, previousIDs: knownRotting, previousThresholds: previousThresholds, thresholds: thresholds) {
                sendPRNotification(title: "A pull request went quiet", pr: item.pull, category: "rotting")
            }
        }
        knownRotting = Set(rotting.map(\.id))
        previousThresholds = thresholds
        guard settings.morningSummary,
              let day = TimelineNotificationPolicy.summaryDay(now: .now, calendar: .current, scheduledMinutes: settings.morningSummaryMinutes,
                                                              refreshMinutes: settings.refreshMinutes, lastDay: settings.lastMorningSummary) else { return nil }
        let waiting = TimelineNotificationPolicy.waitingForReview(items).count
        guard waiting > 0 || !rotting.isEmpty else { return nil }
        sendTimelineNotification(title: "Your pull requests this morning", body: "\(waiting) waiting for your review · \(rotting.count) of yours rotting")
        return day
    }
}

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
