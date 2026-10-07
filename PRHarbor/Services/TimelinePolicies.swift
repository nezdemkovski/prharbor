import Foundation

/// Decisions based on facts already projected for the timeline; no preferences or side effects.
nonisolated enum TimelineNotificationPolicy {
    static func rottingOwned(_ items: [TimelineItem]) -> [TimelineItem] {
        items.filter { $0.isMine && $0.hasKnownQuietPeriod && $0.freshness == .rotting && $0.snoozedUntil == nil }
    }

    static func waitingForReview(_ items: [TimelineItem]) -> [TimelineItem] {
        items.filter { $0.reviewRequested && $0.snoozedUntil == nil }
    }

    static func newlyRotting(_ rotting: [TimelineItem], previousIDs: Set<String>?,
                             previousThresholds: [Int]?, thresholds: [Int]) -> [TimelineItem] {
        guard let previousIDs, previousThresholds == thresholds else { return [] }
        return rotting.filter { !previousIDs.contains($0.id) }
    }

    static func summaryDay(now: Date, calendar: Calendar, scheduledMinutes: Int,
                           refreshMinutes: Int, lastDay: String) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard minutes >= scheduledMinutes, minutes < scheduledMinutes + max(10, refreshMinutes),
              lastDay != day else { return nil }
        return day
    }
}

nonisolated enum TimelineSnoozePolicy {
    static func reconcile(edges: [Edge], snoozed: [String: Double], activity: [String: Double],
                          now: Date, wakeOnComment: Bool, username: String) -> (snoozed: [String: Double], activity: [String: Double]) {
        var snoozed = snoozed
        var activity = activity
        for (url, until) in snoozed {
            let baseline = activity[url] ?? until
            let commented = wakeOnComment && edges.contains { edge in
                edge.node.url.absoluteString == url && TimelinePolicy.events(edge.node).contains {
                    $0.kind == .comment && $0.person?.login != nil
                        && $0.person?.login.caseInsensitiveCompare(username) != .orderedSame
                        && $0.date.timeIntervalSince1970 > baseline
                }
            }
            if until <= now.timeIntervalSince1970 || commented {
                snoozed.removeValue(forKey: url)
                activity.removeValue(forKey: url)
            }
        }
        return (snoozed, activity)
    }
}
