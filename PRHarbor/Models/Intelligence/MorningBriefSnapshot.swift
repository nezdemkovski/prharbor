import Foundation

nonisolated struct MorningBriefSnapshot: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let id: String
        let repository: String
        let number: Int
        let title: String
        let reason: String
        let action: String
    }
    let day: Date
    let waitingForReview: Int
    let quietOwned: Int
    let entries: [Entry]

    init(items: [TimelineItem], now: Date, calendar: Calendar = .current) {
        day = calendar.startOfDay(for: now)
        let eligible = items.filter { !$0.isBot && !$0.pull.isDraft && $0.snoozedUntil == nil }
        waitingForReview = eligible.filter { $0.reviewRequested && !$0.isMine }.count
        quietOwned = eligible.filter { $0.isMine && !$0.isBlocked && $0.hasKnownQuietPeriod && ($0.freshness == .stale || $0.freshness == .rotting) }.count
        func priority(_ item: TimelineItem) -> Int {
            if item.isMine && (item.ci == .failure || item.pull.mergeable == .conflicting || item.pull.reviewDecision == .changesRequested) { return 4 }
            if item.reviewRequested && !item.isMine { return 3 }
            if item.isMine && item.hasKnownQuietPeriod && (item.freshness == .stale || item.freshness == .rotting) { return 2 }
            if item.isMine && item.nextAction == .merge { return 1 }
            return 0
        }
        // Select the lowest eligible layer of each stack before comparing priorities.
        var seen = Set<String>()
        let candidates = eligible.filter { !$0.isBlocked && priority($0) > 0 }
            .sorted { a, b in
                let pa = a.pull.stackEntry?.position ?? 0, pb = b.pull.stackEntry?.position ?? 0
                return pa == pb ? a.id < b.id : pa < pb
            }
            .filter { seen.insert($0.pull.stack?.id ?? $0.id).inserted }
            .sorted { a, b in
                if priority(a) != priority(b) { return priority(a) > priority(b) }
                if a.quietDays != b.quietDays { return a.quietDays > b.quietDays }
                return a.id < b.id
            }
        entries = candidates.prefix(3).map { item in
            var facts: [String] = []
            if item.reviewRequested && !item.isMine { facts.append("Your review is requested") }
            if item.pull.mergeable == .conflicting { facts.append("Merge conflict") }
            if item.ci == .failure { facts.append("Checks are failing") }
            if item.pull.reviewDecision == .changesRequested { facts.append("Changes requested") }
            if item.pull.reviewDecision == .approved { facts.append("Approved") }
            facts.append(item.hasKnownQuietPeriod ? "Quiet for \(Int(item.quietDays)) days" : "Quiet time unknown")
            return Entry(id: item.id, repository: item.pull.repository.nameWithOwner, number: item.pull.number,
                         title: String(item.title.prefix(120)), reason: facts.joined(separator: " · "), action: item.nextAction.title)
        }
    }
}
