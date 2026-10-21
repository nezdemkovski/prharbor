import Defaults
import Foundation
import Observation
import os
import Security

/// Request and sync timings, visible in Console under the "sync" category.
nonisolated let syncLog = Logger(subsystem: "com.nezdemkovski.prharbor", category: "sync")

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

/// GitHub's REST and GraphQL endpoints over HTTPS, authorized with a personal access token.
nonisolated struct GitHubHTTPTransport: GitHubAPITransport {
    /// Ephemeral: authorized responses are never written to the shared URL cache.
    static let urlSession = URLSession(configuration: .ephemeral)

    let apiURL: URL
    let graphQLURL: URL
    private let token: String
    private let session: URLSession

    init(apiBaseURL: String, token: String, session: URLSession = GitHubHTTPTransport.urlSession) throws {
        guard let url = URL(string: apiBaseURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw GitHubAccessError.unsupportedHost
        }
        if apiBaseURL == "https://api.github.com" {
            graphQLURL = url.appendingPathComponent("graphql")
        } else {
            guard url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v3" else {
                throw GitHubAccessError.unsupportedHost
            }
            // GitHub Enterprise serves GraphQL at /api/graphql beside /api/v3.
            graphQLURL = url.deletingLastPathComponent().appendingPathComponent("graphql")
        }
        apiURL = url
        self.token = token
        self.session = session
    }

    func api(_ endpoint: String, body: Data?) async throws -> Data {
        try await send(endpoint, body: body).data
    }

    /// GitHub's new classic token form with the scopes PR Harbor needs already checked,
    /// on github.com or the Enterprise host.
    static func newTokenURL(apiBaseURL: String) -> URL? {
        guard var components = URLComponents(string: apiBaseURL), components.scheme == "https",
              let host = components.host else { return nil }
        components.host = host == "api.github.com" ? "github.com" : host
        components.path = "/settings/tokens/new"
        components.queryItems = [.init(name: "scopes", value: "repo,read:org"), .init(name: "description", value: "PR Harbor")]
        return components.url
    }

    /// The token's account and, for classic tokens, its OAuth scopes. Fine-grained tokens report no scopes.
    func account() async throws -> (user: User, scopes: Set<String>?) {
        let (data, response) = try await send("user", body: nil)
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes").map {
            Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        return (try JSONDecoder().decode(User.self, from: data), scopes)
    }

    private func send(_ endpoint: String, body: Data?) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: endpoint == "graphql" ? graphQLURL : apiURL.appendingPathComponent(endpoint), timeoutInterval: 60)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        syncLog.notice("HTTP \(endpoint, privacy: .public) \(http.statusCode) \(data.count / 1024) KB in \(started.duration(to: .now), privacy: .public), rate limit remaining \(http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?", privacy: .public)")
        if (200..<300).contains(http.statusCode) { return (data, http) }
        if http.statusCode == 401 { throw GitHubAccessError.invalidToken }
        // Primary limits exhaust the remaining count; secondary limits send Retry-After.
        if http.statusCode == 403 || http.statusCode == 429,
           http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || http.value(forHTTPHeaderField: "Retry-After") != nil {
            throw GitHubAccessError.rateLimited(until: Self.retryDate(http))
        }
        // GraphQL failures can carry a non-2xx status; the client interprets their errors,
        // so schema fallbacks and mutation failures keep their GitHub messages.
        if endpoint == "graphql",
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            return (data, http)
        }
        throw GitHubAccessError.requestFailed(status: http.statusCode)
    }

    private static func retryDate(_ response: HTTPURLResponse) -> Date? {
        if let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
            return Date.now.addingTimeInterval(seconds)
        }
        return response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
    }
}

/// Where tokens are kept: the login Keychain in the app, memory in tests.
nonisolated struct GitHubTokenStorage: Sendable {
    var read: @Sendable (_ apiBaseURL: String) throws -> String?
    var save: @Sendable (_ token: String, _ apiBaseURL: String) throws -> Void
    var delete: @Sendable (_ apiBaseURL: String) throws -> Void

    static let keychain = GitHubTokenStorage(
        read: { apiBaseURL in
            var query = keychainQuery(apiBaseURL)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw keychainError(status) }
            return String(data: data, encoding: .utf8)
        },
        save: { token, apiBaseURL in
            let query = keychainQuery(apiBaseURL)
            let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                             kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw keychainError(status) }
        },
        delete: { apiBaseURL in
            let status = SecItemDelete(keychainQuery(apiBaseURL) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
        })

    static func memory() -> GitHubTokenStorage {
        let tokens = TokenBox()
        return GitHubTokenStorage(read: { tokens[$0] }, save: { tokens[$1] = $0 }, delete: { tokens[$0] = nil })
    }

    private static func keychainQuery(_ apiBaseURL: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.nezdemkovski.prharbor",
         kSecAttrAccount as String: "personal-access-token " + apiBaseURL]
    }

    private static func keychainError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

private nonisolated final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    subscript(key: String) -> String? {
        get { lock.withLock { values[key] } }
        set { lock.withLock { values[key] = newValue } }
    }
}

/// Validates a pasted token, then stores it and selects its account.
@MainActor @Observable
final class GitHubTokenConnector {
    private(set) var isConnecting = false
    private(set) var error: String?
    private(set) var successfulConnections = 0
    private let session: GitHubSession
    private var task: Task<Void, Never>?
    private var generation = 0

    init(session: GitHubSession = .shared) { self.session = session }

    func connect(token: String) {
        cancel()
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let epoch = generation
        let sessionEpoch = session.generation
        let baseURL = Defaults[.githubApiBaseUrl]
        isConnecting = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await GitHubHTTPTransport(apiBaseURL: baseURL, token: token).account()
                try Task.checkCancellation()
                guard generation == epoch, session.generation == sessionEpoch,
                      Defaults[.githubApiBaseUrl] == baseURL, !account.user.login.isEmpty else { throw CancellationError() }
                if let scopes = account.scopes, !scopes.contains("repo") { throw GitHubAccessError.missingRepoScope }
                try session.connect(.init(username: account.user.login, apiBaseURL: baseURL), token: token)
                successfulConnections += 1
                isConnecting = false
                task = nil
            } catch is CancellationError {
                if generation == epoch { isConnecting = false; task = nil }
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isConnecting = false
                task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isConnecting = false
    }
}
