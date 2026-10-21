import Combine
import Defaults
import Foundation

/// The connected account and its personal access token.
@MainActor
final class GitHubSession: ObservableObject {
    static let shared = GitHubSession()
    @Published private(set) var connection: GitHubConnection?
    private let tokens: GitHubTokenStorage
    private let persist: (GitHubConnection?) -> Void
    /// Read from the Keychain once per connection rather than on every refresh.
    private var token: String?
    private(set) var generation = 0

    convenience init() {
        if AppRuntime.isTesting {
            self.init(connection: nil)
            return
        }
        let connection = Defaults[.githubConnection]
        Defaults[.githubUsername] = connection?.username ?? ""
        self.init(connection: connection, tokens: .keychain, persist: { value in
            Defaults[.githubConnection] = value
            Defaults[.githubUsername] = value?.username ?? ""
        })
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
