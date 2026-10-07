import Foundation

/// AI proposes tokens; the existing timeline parser remains the authority.
nonisolated struct IntelligenceSearchContext: Equatable, Sendable {
    static let keywords: Set<String> = ["mine", "reviewing", "draft", "snoozed", "blocked", "fresh", "aging", "stale", "rotting", "bots", "failing", "approved", "conflict", "stack", "team", "decide", "unreviewed"]
    let repositories: [String]
    let people: [String]

    init(items: [TimelineItem]) {
        repositories = Array(Set(items.map { $0.pull.repository.nameWithOwner.lowercased() })).sorted()
        people = Array(Set(items.flatMap { item in
            [item.pull.author?.login].compactMap { $0 } + (item.pull.reviewRequests?.nodes ?? []).compactMap { $0.requestedReviewer?.login }
        }.map { $0.lowercased() })).sorted()
    }

    func validatedQuery(_ tokens: [String]) -> String? {
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        var result: [String] = []
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty, token.count <= 160, !token.contains(where: \.isWhitespace) else { return nil }
            let known = Self.keywords.contains(token) || repositories.contains(token) || (token.hasPrefix("@") && people.contains(String(token.dropFirst())))
            let number = token.range(of: #"^#[1-9][0-9]{0,8}$"#, options: .regularExpression) != nil
            let age = token.range(of: #"^[<>][0-9]{1,4}[dwm]?$"#, options: .regularExpression) != nil
            let idle = token.range(of: #"^idle:[0-9]{1,4}d?(-[0-9]{1,4}d?|\+)$"#, options: .regularExpression) != nil && TimelinePolicy.idleRange(token) != nil
            guard known || number || age || idle else { return nil }
            if !result.contains(token) { result.append(token) }
        }
        return result.joined(separator: " ")
    }

    func explicitRepositories(in request: String) -> [String] {
        repositories.filter { repository in
            let name = String(repository.split(separator: "/").last ?? "")
            let unique = repositories.filter { $0.split(separator: "/").last == Substring(name) }.count == 1
            let aliases = [repository] + (unique && name.count > 4 && !Self.keywords.contains(name) ? [name] : [])
            return aliases.contains { alias in
                let pattern = #"(?<![\w./-])"# + NSRegularExpression.escapedPattern(for: alias) + #"(?![\w./-])"#
                return request.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
    }

    func validatedSuggestion(_ tokens: [String], request: String) -> String? {
        let named = explicitRepositories(in: request)
        guard named.count <= 1 else { return nil }
        // A supplied repository list is vocabulary, not a request to filter by every entry.
        let aliases = repositories.compactMap { $0.split(separator: "/").last.map(String.init) }.filter { !Self.keywords.contains($0) }
        let repositoryTokens = Set(repositories + aliases)
        let withoutInferredRepositories = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !repositoryTokens.contains($0) }
        return validatedQuery(withoutInferredRepositories + named)
    }

    func shouldInterpret(_ request: String, hasLiteralMatches: Bool) -> Bool {
        let words = request.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1, !hasLiteralMatches else { return false }
        let aliases: Set<String> = ["my", "review", "reviews", "smelly", "bot", "red", "stacks", "dead"]
        // Existing syntax and literal searches stay immediate, including searches with no results.
        if words.allSatisfy({ Self.keywords.contains($0) || aliases.contains($0) || repositories.contains($0) || $0.hasPrefix("@") || $0.hasPrefix("#") || $0.hasPrefix(">") || $0.hasPrefix("<") || $0.hasPrefix("idle:") }) { return false }
        return request.range(of: #"\b(my|our|show|find|with|without|older|newer|than|quiet|inactive|least|between|waiting|prs|drafts|conflicts|checks|pull requests|мои|покажи|найди|старше|младше|недель|дней|ревью)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

nonisolated struct IntelligenceSearchRequest: Equatable, Sendable {
    let text: String
    let enabled: Bool
    let context: IntelligenceSearchContext
    let hasLiteralMatches: Bool
    var needsInterpretation: Bool { enabled && context.shouldInterpret(text, hasLiteralMatches: hasLiteralMatches) }
}

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
            if item.isMine && (item.ci == .failure || item.pull.mergeable == "CONFLICTING" || item.pull.reviewDecision == "CHANGES_REQUESTED") { return 4 }
            if item.reviewRequested && !item.isMine { return 3 }
            if item.isMine && item.hasKnownQuietPeriod && (item.freshness == .stale || item.freshness == .rotting) { return 2 }
            if item.isMine && item.nextAction == "Merge on GitHub" { return 1 }
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
            if item.pull.mergeable == "CONFLICTING" { facts.append("Merge conflict") }
            if item.ci == .failure { facts.append("Checks are failing") }
            if item.pull.reviewDecision == "CHANGES_REQUESTED" { facts.append("Changes requested") }
            if item.pull.reviewDecision == "APPROVED" { facts.append("Approved") }
            facts.append(item.hasKnownQuietPeriod ? "Quiet for \(Int(item.quietDays)) days" : "Quiet time unknown")
            return Entry(id: item.id, repository: item.pull.repository.nameWithOwner, number: item.pull.number,
                         title: String(item.title.prefix(120)), reason: facts.joined(separator: " · "), action: item.nextAction)
        }
    }
}
