import Foundation

nonisolated enum TimelinePolicy {
    static func validThresholds(_ values: [Int]) -> [Int] {
        guard values.count == 3, values[0] > 0, values[1] > values[0], values[2] > values[1] else { return [2, 7, 21] }
        return values
    }
    static func isBot(_ login: String?, patterns: [String]) -> Bool {
        TimelineBotMatcher(patterns: patterns).matches(login)
    }
    static func days(since date: Date, now: Date) -> Double { max(0, now.timeIntervalSince(date) / 86_400) }
    static func duration(_ days: Double) -> String {
        if days < 1 { return "\(max(1, Int((days * 24).rounded())))h" }
        if days < 60 { return "\(Int(days.rounded()))d" }
        if days < 365 { return "\(Int((days / 30.4).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
    static func idleRange(_ token: String) -> ClosedRange<Double>? {
        guard token.lowercased().hasPrefix("idle:") else { return nil }
        let value = String(token.dropFirst(5)).lowercased()
        func days(_ value: String) -> Double? {
            let number = value.hasSuffix("d") ? String(value.dropLast()) : value
            guard let days = Int(number), days >= 0 else { return nil }
            return Double(days)
        }
        if value.hasSuffix("+"), let lower = days(String(value.dropLast())) { return lower...Double.infinity }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let a = days(parts[0]), let b = days(parts[1]) else { return nil }
        return min(a, b)...max(a, b)
    }
    static func events(_ pull: Pull) -> [TimelineEvent] {
        var result = [TimelineEvent(id: -1, date: pull.createdAt, kind: .opened, person: pull.author)]
        for (i, node) in (pull.timelineItems?.nodes ?? []).compactMap({ $0 }).enumerated() {
            let kind: TimelineEvent.Kind
            let date: Date?
            var person = node.author
            switch node.__typename {
            case "PullRequestCommit":
                kind = .commit
                date = node.commit?.committedDate
            case "IssueComment":
                kind = .comment
                date = node.createdAt
            case "PullRequestReview":
                kind = node.state == .approved ? .approved : node.state == .changesRequested ? .changes : .comment
                date = node.submittedAt
            case "ReviewRequestedEvent":
                kind = .requested
                date = node.createdAt
                if let r = node.requestedReviewer, let login = r.login { person = User(login: login, avatarUrl: r.avatarUrl) }
            default: continue
            }
            if let date { result.append(TimelineEvent(id: i, date: date, kind: kind, person: person)) }
        }
        return result.sorted { $0.date < $1.date }
    }
}
