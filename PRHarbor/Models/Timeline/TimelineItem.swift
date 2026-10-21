import Foundation

nonisolated struct TimelineItem: Identifiable, Equatable, Sendable {
    let pull: Pull
    let events: [TimelineEvent]
    let botPatterns: [String]
    let reviewRequested: Bool
    let isMine: Bool
    let isBot: Bool
    let waitingSince: Date
    /// False when a bounded history omitted the event needed to establish this age.
    let hasKnownQuietPeriod: Bool
    let quietDays: Double
    let age: Double
    let freshness: Freshness
    let checks: [CICheck]
    let blockedBy: StackedPullRequest?
    let snoozedUntil: Date?
    /// The searches that returned this PR. Fixtures without a source belong to every category.
    let sources: PullSources
    var id: String { pull.url.absoluteString }
    let title: String
    let ticket: String?
    let ci: CIStatusKind?
    private let hasHumanReviewRequest: Bool
    var isBlocked: Bool { if case .goToBase = nextAction { true } else { false } }
    var nextAction: NextAction {
        if isBot { return .triage }
        if !isMine { return reviewRequested ? .review : .open }
        if hasKnownQuietPeriod && quietDays >= 60 { return .reviveOrClose }
        if pull.mergeable == .conflicting { return .rebase }
        if ci == .failure { return .fixCI }
        if pull.reviewDecision == .changesRequested { return .addressFeedback }
        if let blockedBy { return .goToBase(blockedBy.number) }
        if pull.isDraft { return .continueDraft }
        if pull.reviewDecision == .approved, ci == .success, pull.mergeable == .mergeable { return .merge }
        if !hasHumanReviewRequest && pull.reviewDecision != .approved { return .askForReview }
        if hasKnownQuietPeriod && quietDays >= 2 && pull.reviewDecision != .approved { return .nudgeReviewers }
        return .open
    }
    var standing: String {
        if isBot { return "Opened \(TimelinePolicy.duration(age)) ago" }
        if let snoozedUntil { return "Snoozed until \(snoozedUntil.formatted(date: .abbreviated, time: .omitted))" }
        if let blockedBy { return "Waits for #\(blockedBy.number)" }
        if !isMine && !reviewRequested { return "Opened \(TimelinePolicy.duration(age)) ago" }
        if !hasKnownQuietPeriod { return isMine ? "Quiet period unknown" : "Waiting on you · since unknown" }
        if !isMine { return "Waiting on you · \(TimelinePolicy.duration(quietDays))" }
        return quietDays < 1 ? "Active today" : "\(TimelinePolicy.duration(quietDays)) quiet"
    }

    init(pull: Pull, username: String, now: Date, thresholds: [Int], bots: [String], ownComments: Bool, snoozedUntil: Date?, reviewRequested: Bool = true, sources: PullSources = .all, botMatcher: TimelineBotMatcher? = nil) {
        let matcher = botMatcher ?? TimelineBotMatcher(patterns: bots)
        let cleaned = pull.title.replacingOccurrences(of: #"^(\s*\[?[A-Z]{2,}-\d+\]?\s*[:,\-–]?\s*)+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        self.title = cleaned.isEmpty ? pull.title : cleaned
        self.ticket = pull.title.range(of: #"\b[A-Z]{2,}-\d+\b"#, options: .regularExpression).map { String(pull.title[$0]) }
        self.hasHumanReviewRequest = (pull.reviewRequests?.nodes ?? []).contains { request in
            guard let reviewer = request.requestedReviewer else { return false }
            if let login = reviewer.login { return !matcher.matches(login) }
            return reviewer.name != nil || reviewer.__typename == "Team"
        }
        self.botPatterns = bots
        self.reviewRequested = reviewRequested
        self.sources = sources
        self.pull = pull
        self.isMine = pull.author?.login.caseInsensitiveCompare(username) == .orderedSame
        self.isBot = matcher.matches(pull.author?.login)
        self.events = TimelinePolicy.events(pull).filter { !matcher.matches($0.person?.login) }
        self.age = TimelinePolicy.days(since: pull.createdAt, now: now)
        self.snoozedUntil = snoozedUntil.flatMap { $0 > now ? $0 : nil }
        let checks = pull.commits.map(CICheck.from) ?? []
        self.checks = checks
        self.ci = ciAggregateStatus(pull.commits)
        let truncated = pull.timelineItems?.pageInfo?.hasPreviousPage == true
        if isMine {
            let relevant = events.filter { $0.kind != .opened && (ownComments || !($0.kind == .comment && $0.person?.login.caseInsensitiveCompare(pull.author?.login ?? "") == .orderedSame)) }
            // Older API fixtures have no history. Never infer a quiet period from an empty timeline.
            self.hasKnownQuietPeriod = !truncated || relevant.last != nil
            self.waitingSince = pull.timelineItems == nil || (truncated && relevant.isEmpty) ? pull.updatedAt : relevant.last?.date ?? pull.createdAt
        } else {
            let request = events.last(where: { $0.kind == .requested && $0.person?.login.caseInsensitiveCompare(username) == .orderedSame })
            self.hasKnownQuietPeriod = !truncated || request != nil
            self.waitingSince = request?.date ?? (truncated ? pull.updatedAt : pull.createdAt)
        }
        let quietDays = TimelinePolicy.days(since: waitingSince, now: now)
        self.quietDays = quietDays
        self.freshness = hasKnownQuietPeriod ? (Freshness.allCases.first { $0.contains(quietDays, thresholds: thresholds) } ?? .rotting) : .fresh
        let open = (pull.stack?.entries?.nodes ?? []).filter { $0.pullRequest?.state == .open }.sorted { $0.position < $1.position }
        self.blockedBy = open.first.flatMap { entry in
            guard let base = entry.pullRequest, base.url != pull.url, (pull.stackEntry?.position ?? 0) > entry.position else { return nil }
            return base
        }
    }

    func matches(_ query: String) -> Bool {
        matches(terms: query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }

    func matches(terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let searchable = "\(pull.title) \(pull.repository.nameWithOwner) \(pull.author?.login ?? "") #\(pull.number) \(pull.headRefName)".lowercased()
        return terms.allSatisfy { term in
            switch term {
            case "mine", "my": return isMine
            case "review", "reviews", "reviewing": return !isMine
            case "draft": return pull.isDraft
            case "snoozed": return snoozedUntil != nil
            case "blocked": return isBlocked
            case "fresh", "aging", "rotting": return hasKnownQuietPeriod && !isBlocked && freshness.rawValue == term
            case "stale", "smelly": return hasKnownQuietPeriod && !isBlocked && (freshness == .stale || freshness == .rotting)
            case "bot", "bots": return isBot
            case "failing", "red": return ci == .failure
            case "approved": return pull.reviewDecision == .approved
            case "conflict": return pull.mergeable == .conflicting
            case "stack", "stacks": return (pull.stack?.size ?? 0) > 1
            case "team": return !isMine && !isBot && !reviewRequested
            case "decide", "dead": return hasKnownQuietPeriod && isMine && quietDays > 60
            case "unreviewed": return nextAction == .askForReview
            default:
                if let idle = TimelinePolicy.idleRange(term) { return hasKnownQuietPeriod && idle.contains(quietDays) }
                if term.hasPrefix("@") {
                    let login = String(term.dropFirst())
                    return pull.author?.login.lowercased() == login || (pull.reviewRequests?.nodes ?? []).contains { $0.requestedReviewer?.login?.lowercased() == login }
                }
                if term.hasPrefix("#"), let number = Int(term.dropFirst()) { return pull.number == number || pull.stack?.number == number }
                if let comparison = term.first, comparison == ">" || comparison == "<" {
                    let value = String(term.dropFirst())
                    let multiplier = value.hasSuffix("w") ? 7.0 : value.hasSuffix("m") ? 30.0 : 1.0
                    let number = value.last?.isLetter == true ? String(value.dropLast()) : value
                    if let days = Double(number) { return comparison == ">" ? age > days * multiplier : age < days * multiplier }
                }
                return searchable.contains(term)
            }
        }
    }
}
