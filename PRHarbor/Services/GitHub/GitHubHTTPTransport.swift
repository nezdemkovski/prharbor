import Foundation
import os

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
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else {
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
            let host = components.host
        else { return nil }
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
        syncLog.notice(
            "HTTP \(endpoint, privacy: .public) \(http.statusCode) \(data.count / 1024) KB in \(started.duration(to: .now), privacy: .public), rate limit remaining \(http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?", privacy: .public)"
        )
        if (200..<300).contains(http.statusCode) { return (data, http) }
        if http.statusCode == 401 { throw GitHubAccessError.invalidToken }
        // Primary limits exhaust the remaining count; secondary limits send Retry-After.
        if http.statusCode == 403 || http.statusCode == 429,
            http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || http.value(forHTTPHeaderField: "Retry-After") != nil
        {
            throw GitHubAccessError.rateLimited(until: Self.retryDate(http))
        }
        // GraphQL failures can carry a non-2xx status; the client interprets their errors,
        // so schema fallbacks and mutation failures keep their GitHub messages.
        if endpoint == "graphql",
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = object["errors"] as? [[String: Any]], !errors.isEmpty
        {
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
