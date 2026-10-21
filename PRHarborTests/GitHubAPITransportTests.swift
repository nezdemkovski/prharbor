import Defaults
import Foundation
import Testing

@testable import PRHarbor

@Suite("GitHub HTTP transport", .serialized)
struct GitHubAPITransportTests {
    private func transport(
        _ baseURL: String = "https://api.github.com", token: String = "ghp_example",
        handler: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)
    ) throws -> GitHubHTTPTransport {
        TransportStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportStubProtocol.self]
        return try GitHubHTTPTransport(apiBaseURL: baseURL, token: token, session: URLSession(configuration: configuration))
    }

    @Test func requestsCarryTheTokenAndReachGraphQLOnEachHost() async throws {
        let recorder = RequestLog()
        let cloud = try transport { request in
            recorder.append(request)
            return (200, [:], Data("{}".utf8))
        }
        _ = try await cloud.api("graphql", body: Data("{}".utf8))
        _ = try await cloud.api("user", body: nil)
        let enterprise = try transport("https://github.example.com/api/v3") { request in
            recorder.append(request)
            return (200, [:], Data("{}".utf8))
        }
        _ = try await enterprise.api("graphql", body: Data("{}".utf8))
        let requests = recorder.requests
        #expect(
            requests.map(\.url?.absoluteString) == [
                "https://api.github.com/graphql", "https://api.github.com/user",
                "https://github.example.com/api/graphql"
            ])
        #expect(requests.map(\.httpMethod) == ["POST", "GET", "POST"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_example" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28" })
    }

    @Test func authenticationAndRateLimitFailuresAreDistinct() async throws {
        await #expect(throws: GitHubAccessError.invalidToken) {
            try await transport { _ in (401, [:], Data(#"{"message":"Bad credentials"}"#.utf8)) }.api("user", body: nil)
        }
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        await #expect(throws: GitHubAccessError.rateLimited(until: reset)) {
            try await transport { _ in (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], Data()) }.api(
                "user", body: nil)
        }
        // A permission failure is not a rate limit.
        await #expect(throws: GitHubAccessError.requestFailed(status: 403)) {
            try await transport { _ in (403, ["X-RateLimit-Remaining": "4000"], Data(#"{"message":"Forbidden"}"#.utf8)) }.api(
                "user", body: nil)
        }
    }

    @Test func graphQLErrorsReachTheClientWhateverTheStatus() async throws {
        let body = Data(#"{"errors":[{"message":"Branch has conflicts"}]}"#.utf8)
        #expect(try await transport { _ in (422, [:], body) }.api("graphql", body: Data("{}".utf8)) == body)
        await #expect(throws: GitHubAccessError.requestFailed(status: 502)) {
            try await transport { _ in (502, [:], Data("<html>".utf8)) }.api("graphql", body: Data("{}".utf8))
        }
    }

    @Test func accountReportsClassicScopesOnly() async throws {
        let classic = try await transport { _ in (200, ["X-OAuth-Scopes": "repo, read:org"], Data(#"{"login":"octocat"}"#.utf8)) }.account()
        #expect(classic.user.login == "octocat")
        #expect(classic.scopes == ["repo", "read:org"])
        let fineGrained = try await transport { _ in (200, [:], Data(#"{"login":"octocat"}"#.utf8)) }.account()
        #expect(fineGrained.scopes == nil)
    }

    @Test func searchesAnsweredByAnotherAccountAreRejected() async throws {
        let response = Data(
            #"{"data":{"viewer":{"login":"someone-else"},"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
                .utf8)
        let http = try transport { _ in (200, [:], response) }
        let client = try GitHubClient(baseURL: "https://api.github.com", buildType: .none, transport: http, expectedLogin: "octocat")
        await #expect(throws: GitHubAccessError.accountChanged) { try await client.fetchPulls(filter: "author:octocat") }
        let unchecked = try GitHubClient(baseURL: "https://api.github.com", buildType: .none, transport: http)
        #expect(try await unchecked.fetchPulls(filter: "author:octocat").isEmpty)
    }

    @Test func newTokenLinksPreselectTheNeededScopesOnTheRightHost() {
        #expect(
            GitHubHTTPTransport.newTokenURL(apiBaseURL: "https://api.github.com")?.absoluteString
                == "https://github.com/settings/tokens/new?scopes=repo,read:org&description=PR%20Harbor")
        #expect(
            GitHubHTTPTransport.newTokenURL(apiBaseURL: "https://github.example.com/api/v3")?.absoluteString
                == "https://github.example.com/settings/tokens/new?scopes=repo,read:org&description=PR%20Harbor")
        #expect(GitHubHTTPTransport.newTokenURL(apiBaseURL: "not a url") == nil)
    }

    @Test func enterpriseHostIsExplicitAndInvalidHostsAreRejected() throws {
        #expect(
            try GitHubHTTPTransport(apiBaseURL: "https://github.example.com/api/v3", token: "t").graphQLURL.absoluteString
                == "https://github.example.com/api/graphql")
        #expect(throws: GitHubAccessError.unsupportedHost) { try GitHubHTTPTransport(apiBaseURL: "https://github.com/other", token: "t") }
        #expect(throws: GitHubAccessError.unsupportedHost) { try GitHubHTTPTransport(apiBaseURL: "http://api.github.com", token: "t") }
    }
}

private nonisolated final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { values.append(request) } }
    var requests: [URLRequest] { lock.withLock { values } }
}

/// Separate from MockURLProtocol so this suite never races GitHubClientTests for a handler.
private nonisolated final class TransportStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return client!.urlProtocol(self, didFailWithError: URLError(.unknown)) }
        let (status, headers, data) = handler(request)
        client?.urlProtocol(
            self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
