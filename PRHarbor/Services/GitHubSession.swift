import Combine
import Defaults
import Foundation

/// The selected gh account; PR Harbor never owns an authentication token.
@MainActor
final class GitHubSession: ObservableObject {
    static let shared = GitHubSession()
    @Published private(set) var cliConnection: GitHubCLIConnection?
    private let persist: (GitHubCLIConnection?) -> Void
    private(set) var generation = 0

    convenience init() {
        if AppRuntime.isTesting {
            self.init(connection: nil)
            return
        }
        let connection = Defaults[.githubCLIConnection]
        Defaults[.githubUsername] = connection?.username ?? ""
        self.init(connection: connection, persist: { value in
            Defaults[.githubCLIConnection] = value
            Defaults[.githubUsername] = value?.username ?? ""
        })
    }

    init(connection: GitHubCLIConnection? = nil, persist: @escaping (GitHubCLIConnection?) -> Void = { _ in }) {
        cliConnection = connection
        self.persist = persist
    }

    var isConfigured: Bool {
        cliConnection.map { !$0.username.isEmpty && $0.apiBaseURL == Defaults[.githubApiBaseUrl] } ?? false
    }

    func useCLI(_ connection: GitHubCLIConnection) {
        generation += 1
        persist(connection)
        cliConnection = connection
    }

    func disconnect() {
        generation += 1
        persist(nil)
        cliConnection = nil
    }

    func client(baseURL: String, buildType: BuildType) async throws -> GitHubClient {
        guard let connection = cliConnection, connection.apiBaseURL == baseURL else {
            throw GitHubCLIError.signInRequired
        }
        // The client verifies the answering account within each search and before mutations,
        // so a changed gh account is detected without a separate request.
        let cli = try GitHubCLI(executablePath: connection.executablePath, apiBaseURL: baseURL)
        return try GitHubClient(baseURL: baseURL, buildType: buildType, transport: cli, expectedLogin: connection.username)
    }
}
