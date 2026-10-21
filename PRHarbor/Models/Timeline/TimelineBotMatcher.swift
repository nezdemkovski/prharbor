import Foundation

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
