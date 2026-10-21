import Defaults
import Foundation
import Observation

/// The connected account and its personal access token.
@MainActor @Observable
final class GitHubSession {
    private(set) var connection: GitHubConnection?
    private let tokens: GitHubTokenStorage
    private let persist: (GitHubConnection?) -> Void
    /// Read from the Keychain once per connection rather than on every refresh.
    private var token: String?
    private(set) var generation = 0

    /// The saved account, with its token in the login Keychain.
    static func live() -> GitHubSession {
        GitHubSession(connection: Defaults[.githubConnection], tokens: .keychain, persist: { Defaults[.githubConnection] = $0 })
    }

    init(connection: GitHubConnection? = nil, tokens: GitHubTokenStorage = .memory(),
         persist: @escaping (GitHubConnection?) -> Void = { _ in }) {
        self.connection = connection
        self.tokens = tokens
        self.persist = persist
    }

    var isConfigured: Bool {
        connection.map { !$0.username.isEmpty && $0.apiBaseURL == Defaults[.githubApiBaseUrl] } ?? false
    }

    func connect(_ connection: GitHubConnection, token: String) throws {
        try tokens.save(token, connection.apiBaseURL)
        generation += 1
        self.token = token
        persist(connection)
        self.connection = connection
    }

    /// The account lives in preferences, which start empty inside the sandbox container, while the
    /// token stays in the Keychain. Without a saved account, a saved token for this host restores it.
    func restoreFromSavedToken(baseURL: String, login: ((_ token: String) async throws -> String)? = nil) async {
        let login = login ?? { try await GitHubHTTPTransport(apiBaseURL: baseURL, token: $0).account().user.login }
        guard connection == nil, let token = try? tokens.read(baseURL),
              let username = try? await login(token), connection == nil, !username.isEmpty else { return }
        try? connect(GitHubConnection(username: username, apiBaseURL: baseURL), token: token)
    }

    func disconnect() {
        if let connection { try? tokens.delete(connection.apiBaseURL) }
        generation += 1
        token = nil
        persist(nil)
        connection = nil
    }

    func client(baseURL: String, buildType: BuildType) async throws -> GitHubClient {
        guard let connection, connection.apiBaseURL == baseURL else { throw GitHubAccessError.signInRequired }
        if token == nil { token = try tokens.read(baseURL) }
        guard let token else { throw GitHubAccessError.signInRequired }
        // Each search response confirms the token still answers for this account.
        let transport = try GitHubHTTPTransport(apiBaseURL: baseURL, token: token)
        return try GitHubClient(baseURL: baseURL, buildType: buildType, transport: transport, expectedLogin: connection.username)
    }
}
