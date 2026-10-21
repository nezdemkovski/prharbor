import Defaults
import Foundation

/// The connected account. Its token lives in the Keychain, never in preferences.
nonisolated struct GitHubConnection: Codable, Defaults.Serializable, Equatable, Sendable {
    let username: String
    let apiBaseURL: String
}

nonisolated enum GitHubAccessError: LocalizedError, Equatable {
    case signInRequired, invalidToken, missingRepoScope, accountChanged, unsupportedHost
    case rateLimited(until: Date?)
    case requestFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .signInRequired: "Add a GitHub personal access token in Settings → Account."
        case .invalidToken: "GitHub rejected the token. It may have expired or been revoked; add a new one in Settings → Account."
        case .missingRepoScope: "This token lacks the repo scope, so private pull requests would be missing. Create a token with repo and read:org."
        case .accountChanged: "The saved token now answers for a different GitHub account. Reconnect in Settings → Account."
        case .unsupportedHost: "Use https://api.github.com or your GitHub Enterprise URL ending in /api/v3."
        case .rateLimited(let until):
            until.map { "GitHub's rate limit was reached. Try again after \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "GitHub's rate limit was reached. Try again in a few minutes."
        case .requestFailed(let status): "GitHub returned HTTP \(status). Try again in a moment."
        }
    }
}
