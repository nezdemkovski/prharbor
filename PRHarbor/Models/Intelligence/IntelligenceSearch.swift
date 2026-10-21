import Foundation

/// AI proposes tokens; the existing timeline parser remains the authority.
nonisolated struct IntelligenceSearchContext: Equatable, Sendable {
    static let keywords: Set<String> = [
        "mine", "reviewing", "draft", "snoozed", "blocked", "fresh", "aging", "stale", "rotting", "bots", "failing", "approved", "conflict",
        "stack", "team", "decide", "unreviewed"
    ]
    let repositories: [String]
    let people: [String]

    init(items: [TimelineItem]) {
        repositories = Array(Set(items.map { $0.pull.repository.nameWithOwner.lowercased() })).sorted()
        people = Array(
            Set(
                items.flatMap { item in
                    [item.pull.author?.login].compactMap { $0 }
                        + (item.pull.reviewRequests?.nodes ?? []).compactMap { $0.requestedReviewer?.login }
                }.map { $0.lowercased() })
        ).sorted()
    }

    func validatedQuery(_ tokens: [String]) -> String? {
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        var result: [String] = []
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty, token.count <= 160, !token.contains(where: \.isWhitespace) else { return nil }
            let known =
                Self.keywords.contains(token) || repositories.contains(token)
                || (token.hasPrefix("@") && people.contains(String(token.dropFirst())))
            let number = token.range(of: #"^#[1-9][0-9]{0,8}$"#, options: .regularExpression) != nil
            let age = token.range(of: #"^[<>][0-9]{1,4}[dwm]?$"#, options: .regularExpression) != nil
            let idle =
                token.range(of: #"^idle:[0-9]{1,4}d?(-[0-9]{1,4}d?|\+)$"#, options: .regularExpression) != nil
                && TimelinePolicy.idleRange(token) != nil
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
        let withoutInferredRepositories = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter {
            !repositoryTokens.contains($0)
        }
        return validatedQuery(withoutInferredRepositories + named)
    }

    func shouldInterpret(_ request: String, hasLiteralMatches: Bool) -> Bool {
        let words = request.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1, !hasLiteralMatches else { return false }
        let aliases: Set<String> = ["my", "review", "reviews", "smelly", "bot", "red", "stacks", "dead"]
        // Existing syntax and literal searches stay immediate, including searches with no results.
        if words.allSatisfy({
            Self.keywords.contains($0) || aliases.contains($0) || repositories.contains($0) || $0.hasPrefix("@") || $0.hasPrefix("#")
                || $0.hasPrefix(">") || $0.hasPrefix("<") || $0.hasPrefix("idle:")
        }) {
            return false
        }
        return request.range(
            of:
                #"\b(my|our|show|find|with|without|older|newer|than|quiet|inactive|least|between|waiting|prs|drafts|conflicts|checks|pull requests|мои|покажи|найди|старше|младше|недель|дней|ревью)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }
}

nonisolated struct IntelligenceSearchRequest: Equatable, Sendable {
    let text: String
    let enabled: Bool
    let context: IntelligenceSearchContext
    let hasLiteralMatches: Bool
    var needsInterpretation: Bool { enabled && context.shouldInterpret(text, hasLiteralMatches: hasLiteralMatches) }
}
