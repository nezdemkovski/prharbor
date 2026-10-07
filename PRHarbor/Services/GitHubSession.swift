import Combine
import Defaults
import Foundation
import LocalAuthentication
import Security

/// The selected gh account; PR Harbor never owns an authentication token.
@MainActor
final class GitHubSession: ObservableObject {
    static let shared = GitHubSession()
    @Published private(set) var cliConnection: GitHubCLIConnection?
    @Published private(set) var cleanupError: String?
    private let persist: (GitHubCLIConnection?) -> Void
    private var cleanupTask: Task<Void, Never>?
    private(set) var generation = 0

    convenience init() {
        if AppRuntime.isTesting {
            self.init(connection: nil)
            return
        }
        let defaults = AppPreferences.storage
        let connection = Self.migratedConnection(Defaults[.githubCLIConnection],
                                                legacyMethod: defaults.string(forKey: "githubConnectionMethod"))
        Defaults[.githubCLIConnection] = connection
        Defaults[.githubUsername] = connection?.username ?? ""
        defaults.removeObject(forKey: "githubConnectionMethod")
        self.init(connection: connection, persist: { value in
            Defaults[.githubCLIConnection] = value
            Defaults[.githubUsername] = value?.username ?? ""
        })
        cleanupLegacyCredentials()
    }

    init(connection: GitHubCLIConnection? = nil, persist: @escaping (GitHubCLIConnection?) -> Void = { _ in }) {
        cliConnection = connection
        self.persist = persist
    }

    static func migratedConnection(_ saved: GitHubCLIConnection?, legacyMethod: String?,
                                   findExecutable: () throws -> String = { try GitHubCLI.findExecutable() }) -> GitHubCLIConnection? {
        // Previous versions retained CLI metadata even after choosing another method or signing out.
        guard legacyMethod == nil || legacyMethod == "cli" else { return nil }
        guard let saved else { return nil }
        // Keep the account even if gh was uninstalled. A later request reports the
        // installation error and can resolve the old bridge path once gh returns.
        guard let path = try? GitHubCLI.resolvedExecutablePath(saved.executablePath, findExecutable: findExecutable) else { return saved }
        return GitHubCLIConnection(executablePath: path, username: saved.username, apiBaseURL: saved.apiBaseURL)
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
        let epoch = generation
        let cli = try GitHubCLI(executablePath: connection.executablePath, apiBaseURL: baseURL)
        let client = try GitHubClient(baseURL: baseURL, buildType: buildType, transport: cli)
        let user = try await client.fetchUser()
        try Task.checkCancellation()
        guard epoch == generation else { throw CancellationError() }
        guard user.login == connection.username else { throw GitHubCLIError.accountChanged }
        return client
    }

    func cleanupLegacyCredentials() {
        guard !AppRuntime.isTesting, cleanupTask == nil, !AppPreferences.storage.bool(forKey: "cliOnlyCredentialsCleanedV1") else { return }
        cleanupError = nil
        cleanupTask = Task { [weak self] in
            do {
                try await LegacyGitHubCredentialCleanup.remove()
                AppPreferences.storage.set(true, forKey: "cliOnlyCredentialsCleanedV1")
            } catch {
                self?.cleanupError = "Could not remove PR Harbor’s previous saved sign-in. Your GitHub CLI connection is unaffected."
            }
            self?.cleanupTask = nil
        }
    }
}

/// One-time migration only. No reading, writing, or revoking authentication credentials.
nonisolated enum LegacyGitHubCredentialCleanup {
    static let service = "com.nezdemkovski.prharbor"
    static func queries(service: String = LegacyGitHubCredentialCleanup.service) -> [[String: Any]] {
        ["githubToken", "githubSession"].map { account in
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }
    }

    @concurrent static func remove() async throws {
        let context = LAContext()
        context.interactionNotAllowed = true
        for var query in queries() {
            query[kSecUseAuthenticationContext as String] = context
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }
    }
}
