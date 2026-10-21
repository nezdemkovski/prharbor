import Foundation

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
