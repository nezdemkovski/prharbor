import Foundation

nonisolated enum TimelineTab: String, CaseIterable, Identifiable, Sendable {
    case all = "All", mine = "Mine", reviewing = "Reviewing"
    var id: Self { self }
}

nonisolated enum Freshness: String, CaseIterable, Identifiable, Sendable {
    case fresh, aging, stale, rotting
    var id: Self { self }
    func contains(_ days: Double, thresholds: [Int]) -> Bool {
        let t = TimelinePolicy.validThresholds(thresholds)
        switch self {
        case .fresh: return days < Double(t[0])
        case .aging: return days >= Double(t[0]) && days < Double(t[1])
        case .stale: return days >= Double(t[1]) && days < Double(t[2])
        case .rotting: return days >= Double(t[2])
        }
    }
}

nonisolated struct TimelineScale: Equatable {
    let days: Int
    var isLogarithmic: Bool { days == 182 }
    func position(age: Double) -> Double {
        let fraction = isLogarithmic ? log1p(max(0, age) / 4) / log1p(Double(days) / 4) : max(0, age) / Double(days)
        return min(1, max(0, 1 - fraction))
    }
    func age(at position: Double) -> Double {
        let p = min(1, max(0, position))
        return isLogarithmic ? 4 * expm1((1 - p) * log1p(Double(days) / 4)) : (1 - p) * Double(days)
    }
    func snappedAge(_ age: Double) -> Double {
        let candidates = [0, 1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120, 182].filter { $0 < days }.map(Double.init) + [Double(days)]
        let x = position(age: age)
        return candidates.min { abs(position(age: $0) - x) < abs(position(age: $1) - x) } ?? 0
    }
    var ticks: [Double] {
        switch days {
        case 14: [14, 10, 7, 3, 0]
        case 30: [30, 21, 14, 7, 0]
        case 90: [90, 60, 30, 14, 0]
        default: [182, 90, 30, 14, 7, 0]
        }
    }
}

nonisolated struct TimelineEvent: Identifiable, Equatable {
    let id: Int
    let date: Date
    let kind: Kind
    let person: User?
    enum Kind: String { case opened, commit, comment, approved, changes, requested }
    var label: String {
        let name = person?.login ?? "a team"
        switch kind {
        case .opened: return "Opened"
        case .commit: return "Commit pushed"
        case .comment: return "\(name) commented"
        case .approved: return "Approved by \(name)"
        case .changes: return "Changes requested by \(name)"
        case .requested: return "Review requested from \(name)"
        }
    }
}

/// Compile account patterns once when PR data or bot settings change.
nonisolated struct TimelineBotMatcher: Sendable {
    private let expressions: [NSRegularExpression]
    init(patterns: [String]) {
        expressions = patterns.compactMap { pattern in
            let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
            return try? NSRegularExpression(pattern: regex, options: .caseInsensitive)
        }
    }
    func matches(_ login: String?) -> Bool {
        guard let login else { return false }
        let range = NSRange(login.startIndex..<login.endIndex, in: login)
        return expressions.contains { $0.firstMatch(in: login, range: range) != nil }
    }
}

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
            guard let days = Int(number), days >= 0 else { return nil }; return Double(days)
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
            case "PullRequestCommit": kind = .commit; date = node.commit?.committedDate
            case "IssueComment": kind = .comment; date = node.createdAt
            case "PullRequestReview":
                kind = node.state == "APPROVED" ? .approved : node.state == "CHANGES_REQUESTED" ? .changes : .comment
                date = node.submittedAt
            case "ReviewRequestedEvent":
                kind = .requested; date = node.createdAt
                if let r = node.requestedReviewer, let login = r.login { person = User(login: login, avatarUrl: r.avatarUrl) }
            default: continue
            }
            if let date { result.append(TimelineEvent(id: i, date: date, kind: kind, person: person)) }
        }
        return result.sorted { $0.date < $1.date }
    }
}

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
    var id: String { pull.url.absoluteString }
    let title: String
    let ticket: String?
    let ci: CIStatusKind?
    private let hasHumanReviewRequest: Bool
    var isBlocked: Bool { nextAction.hasPrefix("Go to #") }
    var nextAction: String {
        if isBot { return "Triage" }
        if !isMine { return reviewRequested ? "Review" : "Open on GitHub" }
        if hasKnownQuietPeriod && quietDays >= 60 { return "Revive or close" }
        if pull.mergeable == "CONFLICTING" { return "Rebase" }
        if ci == .failure { return "Fix CI" }
        if pull.reviewDecision == "CHANGES_REQUESTED" { return "Address feedback" }
        if let blockedBy { return "Go to #\(blockedBy.number)" }
        if pull.isDraft { return "Continue draft" }
        if pull.reviewDecision == "APPROVED", ci == .success, pull.mergeable == "MERGEABLE" { return "Merge on GitHub" }
        if !hasHumanReviewRequest && pull.reviewDecision != "APPROVED" { return "Ask for review" }
        if hasKnownQuietPeriod && quietDays >= 2 && pull.reviewDecision != "APPROVED" { return "Nudge reviewers" }
        return "Open on GitHub"
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

    init(pull: Pull, username: String, now: Date, thresholds: [Int], bots: [String], ownComments: Bool, snoozedUntil: Date?, reviewRequested: Bool = true, botMatcher: TimelineBotMatcher? = nil) {
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
        let open = (pull.stack?.entries?.nodes ?? []).filter { $0.pullRequest?.state == "OPEN" }.sorted { $0.position < $1.position }
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
            case "approved": return pull.reviewDecision == "APPROVED"
            case "conflict": return pull.mergeable == "CONFLICTING"
            case "stack", "stacks": return (pull.stack?.size ?? 0) > 1
            case "team": return !isMine && !isBot && !reviewRequested
            case "decide", "dead": return hasKnownQuietPeriod && isMine && quietDays > 60
            case "unreviewed": return nextAction == "Ask for review"
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

// Parse GitHub history once per input change, rather than for every row and toolbar control.
nonisolated struct TimelineInput: Equatable, Sendable {
    var edges: [Edge]
    var reviewURLs: Set<URL>
    var username: String
    var now: Date
    var thresholds: [Int]
    var bots: [String]
    var ownComments: Bool
    var snoozed: [String: Double]

    init(edges: [Edge], reviewURLs: Set<URL>, username: String, now: Date,
         thresholds: [Int], bots: [String], ownComments: Bool, snoozed: [String: Double]) {
        self.edges = edges
        self.reviewURLs = reviewURLs
        self.username = username
        self.now = now
        self.thresholds = thresholds
        self.bots = bots
        self.ownComments = ownComments
        self.snoozed = snoozed
    }

    init(assigned: [Edge], created: [Edge], requested: [Edge],
         includeAssigned: Bool = true, includeCreated: Bool = true, includeRequested: Bool = true,
         username: String, now: Date, thresholds: [Int], bots: [String],
         ownComments: Bool, snoozed: [String: Double]) {
        self.init(edges: (includeRequested ? requested : []) + (includeAssigned ? assigned : []) + (includeCreated ? created : []),
                  reviewURLs: Set(requested.map { $0.node.url }), username: username, now: now,
                  thresholds: thresholds, bots: bots, ownComments: ownComments, snoozed: snoozed)
    }
    func makeItems() -> [TimelineItem] {
        var seen = Set<String>()
        let matcher = TimelineBotMatcher(patterns: bots)
        return edges.filter { seen.insert($0.node.url.absoluteString).inserted }.map { edge in
            TimelineItem(pull: edge.node, username: username, now: now, thresholds: thresholds,
                         bots: bots, ownComments: ownComments,
                         snoozedUntil: snoozed[edge.node.url.absoluteString].map { Date(timeIntervalSince1970: $0) },
                         reviewRequested: reviewURLs.contains(edge.node.url), botMatcher: matcher)
        }
    }
}


/// One immutable presentation per data/filter change. View updates never regroup PRs.
nonisolated struct TimelinePresentation: Equatable, Sendable {
    enum Row: Identifiable, Equatable, Sendable {
        case repository(name: String, items: [TimelineItem], collapsed: Bool)
        case pull(TimelineItem)
        case stack(PullDisplayGroup, items: [TimelineItem])
        func normalizedSelection(_ selection: String?) -> String? {
            guard let selection else { return nil }
            switch self {
            case .repository: return nil
            case .pull(let item): return item.id == selection ? selection : nil
            case .stack(_, let items): return items.contains { $0.id == selection } ? selection : nil
            }
        }
        var id: String {
            switch self {
            case .repository(let name, _, _): "repo:" + name
            case .pull(let item): "pull:" + item.id
            case .stack(let group, _): "stack:" + group.id
            }
        }
    }
    private(set) var rows: [Row] = []
    private(set) var visibleIDs: Set<String> = []
    private(set) var navigationIDs: [String] = []
    private(set) var itemsByID: [String: TimelineItem] = [:]
    private(set) var contentHeight: CGFloat = TimelineRowGeometry.documentBottomPadding
    private(set) var scrollTargets: [String: String] = [:]
    private(set) var rowRanges: [String: Range<CGFloat>] = [:]
    private(set) var showOwner = false

    init(items: [TimelineItem] = [], tab: TimelineTab = .all, query: String = "",
         sortOrder: SortOrder = .updatedNewest, brush: ClosedRange<Double>? = nil, collapsed: [String] = []) {
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        showOwner = Set(items.map { $0.pull.repository.nameWithOwner.split(separator: "/").first }).count > 1
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let visible = items.filter { item in
            (tab == .all || (tab == .mine ? item.isMine : !item.isMine))
                && item.matches(terms: terms) && (brush.map { item.hasKnownQuietPeriod && $0.contains(item.quietDays) } ?? true)
        }.sorted { a, b in
            let first: Date, second: Date
            switch sortOrder {
            case .updatedNewest, .updatedOldest: first = a.pull.updatedAt; second = b.pull.updatedAt
            case .createdNewest, .createdOldest: first = a.pull.createdAt; second = b.pull.createdAt
            }
            if first == second { return a.id < b.id }
            return sortOrder == .updatedNewest || sortOrder == .createdNewest ? first > second : first < second
        }
        visibleIDs = Set(visible.map(\.id))
        let allByRepo = Dictionary(grouping: items) { $0.pull.repository.nameWithOwner }
        let grouped = Dictionary(grouping: visible) { $0.isBot ? "Bots" : $0.pull.repository.nameWithOwner }
        let names = grouped.keys.sorted { a, b in
            if a == "Bots" { return false }; if b == "Bots" { return true }; return a < b
        }
        let collapsed = Set(collapsed)
        for name in names {
            let matched = grouped[name] ?? []
            let isCollapsed = name == "Bots" ? !collapsed.contains(name) : collapsed.contains(name)
            rows.append(.repository(name: name, items: matched, collapsed: isCollapsed))
            guard !isCollapsed else { continue }
            // Keep companion layers visible when one layer of a stack matches the filter.
            let stackIDs = Set(matched.compactMap { $0.pull.stack?.id })
            let known = Set(matched.map(\.id))
            let companions = (allByRepo[name] ?? []).filter {
                !known.contains($0.id) && $0.pull.stack.map { stackIDs.contains($0.id) } == true
            }
            for group in groupPullsForDisplay((matched + companions).map { Edge(node: $0.pull) }) {
                let unitItems = group.edges.compactMap { itemsByID[$0.node.url.absoluteString] }
                if group.stack != nil, name != "Bots" {
                    rows.append(.stack(group, items: unitItems))
                    let hidden = collapsed.contains("stack:" + group.id)
                    if !hidden {
                        navigationIDs += unitItems.map(\.id)
                        for item in unitItems { scrollTargets[item.id] = "stack:" + group.id }
                    }
                } else {
                    rows += unitItems.map(Row.pull)
                    navigationIDs += unitItems.map(\.id)
                    for item in unitItems { scrollTargets[item.id] = "pull:" + item.id }
                }
            }
        }
        var y: CGFloat = 0
        for row in rows {
            let height: CGFloat
            switch row {
            case .repository: height = TimelineRowGeometry.repositoryHeight
            case .pull(let item):
                height = TimelineRowGeometry.pullHeight
                rowRanges[item.id] = y..<(y + height)
            case .stack(let group, let layers):
                let hidden = collapsed.contains("stack:" + group.id)
                height = TimelineRowGeometry.stackHeight(layers: layers.count, collapsed: hidden)
                if !hidden {
                    for (index, item) in layers.enumerated() {
                        rowRanges[item.id] = TimelineRowGeometry.layerRange(index: index, origin: y)
                    }
                }
            }
            rowRanges[row.id] = y..<(y + height)
            y += height
        }
        contentHeight = y + TimelineRowGeometry.documentBottomPadding
    }
}
