import Foundation

/// Decides what a completed refresh announces: newly listed PRs, PRs that went quiet,
/// and the morning summary. Restored cache and the first fetch never notify.
@MainActor
final class PullNotificationCoordinator {
    private let delivery: NotificationDelivery
    private var reviewRequested = PullRefreshTracker()
    private var assigned = PullRefreshTracker()
    private var created = PullRefreshTracker()
    private var hasLoadedOnce = false
    private var knownRotting: Set<String>?
    private var previousThresholds: [Int]?

    init(delivery: NotificationDelivery = NotificationDelivery()) {
        self.delivery = delivery
    }

    /// Returns the day of a morning summary it sent, for the caller to remember.
    @discardableResult
    func refreshed(assigned: [Edge], created: [Edge], requested: [Edge], fetched: PullSources,
                   items: [TimelineItem], settings: PullRequestSettings) -> String? {
        let newRequested = reviewRequested.update(edges: requested, fetched: fetched.contains(.requested), canNotify: hasLoadedOnce)
        let newAssigned = self.assigned.update(edges: assigned, fetched: fetched.contains(.assigned), canNotify: hasLoadedOnce)
        let newCreated = self.created.update(edges: created, fetched: fetched.contains(.created), canNotify: hasLoadedOnce)
        if hasLoadedOnce {
            delivery.announceNew(requested: newRequested, assigned: newAssigned, created: newCreated, settings: settings)
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
                delivery.pullRequest(item.pull, title: "A pull request went quiet", category: .rotting)
            }
        }
        knownRotting = Set(rotting.map(\.id))
        previousThresholds = thresholds
        guard settings.morningSummary,
              let day = TimelineNotificationPolicy.summaryDay(now: .now, calendar: .current, scheduledMinutes: settings.morningSummaryMinutes,
                                                              refreshMinutes: settings.refreshMinutes, lastDay: settings.lastMorningSummary) else { return nil }
        let waiting = TimelineNotificationPolicy.waitingForReview(items).count
        guard waiting > 0 || !rotting.isEmpty else { return nil }
        delivery.message(title: "Your pull requests this morning", body: "\(waiting) waiting for your review · \(rotting.count) of yours rotting")
        return day
    }
}
