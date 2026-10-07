import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

typealias Edge = PRHarbor.Edge

nonisolated final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var bodies: [Data?] = []

    func record(body: Data?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        bodies.append(body)
        return bodies.count
    }
}

nonisolated func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)

    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { return nil }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

nonisolated func query(from body: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = object as? [String: Any],
          let query = dictionary["query"] as? String else {
        throw URLError(.cannotParseResponse)
    }
    return query
}

nonisolated func rebasePullRequestID(from body: Data) throws -> String {
    try rebaseInputValue("pullRequestId", from: body)
}

nonisolated func rebaseInputValue(_ key: String, from body: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = object as? [String: Any],
          let variables = dictionary["variables"] as? [String: Any],
          let input = variables["input"] as? [String: Any],
          let value = input[key] as? String else {
        throw URLError(.cannotParseResponse)
    }
    return value
}

nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

nonisolated struct CLIExecutableFixture: Sendable {
    let directory: URL
    var executable: URL { directory.appendingPathComponent("gh") }
    var arguments: URL { directory.appendingPathComponent("arguments") }
    var input: URL { directory.appendingPathComponent("input") }
    var environment: URL { directory.appendingPathComponent("environment") }

    init(response: Data, stderr: Data = Data(), exitStatus: Int = 0, wait: Bool = false, fallbackStacks: Bool = false, delay: TimeInterval = 0) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("prharbor-cli-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try response.write(to: directory.appendingPathComponent("response"))
        try stderr.write(to: directory.appendingPathComponent("error"))
        try Data(#"{"errors":[{"message":"Field 'stack' doesn't exist on type 'PullRequest'"}]}"#.utf8).write(to: directory.appendingPathComponent("missing-stack"))
        let quotedDirectory = "'" + directory.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        let script = """
        #!/bin/sh
        set -eu
        cd \(quotedDirectory)
        printf '%s\\n' "$@" > arguments
        /bin/cat > input
        printf '%s' "${GH_PROMPT_DISABLED-}" > environment
        if [ -n "${GH_TOKEN-}" ]; then printf '|present' >> environment; else printf '|absent' >> environment; fi
        if [ -n "${GH_DEBUG-}" ]; then printf '|present' >> environment; else printf '|absent' >> environment; fi
        \(wait ? "exec /bin/sleep 30" : "")
        \(delay > 0 ? "/bin/sleep \(delay)" : "")
        \(fallbackStacks ? "if /usr/bin/grep -Fq 'stack {' input; then /bin/cat missing-stack; exit 1; fi" : "")
        if [ "$2" = user ]; then
            printf '%s' '{"login":"octocat"}'
        else
            /bin/cat response
        fi
        /bin/cat error >&2
        exit \(exitStatus)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

nonisolated struct TestGitHubTransport: GitHubAPITransport {
    let baseURL: URL
    let session: URLSession

    static func client(baseURL: String, buildType: BuildType, session: URLSession = .shared) throws -> GitHubClient {
        let url = try #require(URL(string: baseURL))
        return try GitHubClient(baseURL: baseURL, buildType: buildType, transport: Self(baseURL: url, session: session))
    }

    func api(_ endpoint: String, body: Data?) async throws -> Data {
        let root = endpoint == "graphql" && baseURL.path.hasSuffix("/api/v3") ? baseURL.deletingLastPathComponent() : baseURL
        var request = URLRequest(url: root.appendingPathComponent(endpoint))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        let (data, _) = try await session.data(for: request)
        return data
    }
}

actor PullFetchGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

nonisolated struct ProgressivePullTransport: GitHubAPITransport {
    let gate: PullFetchGate
    let edge: Edge
    var failRequested = true
    func api(_ endpoint: String, body: Data?) async throws -> Data {
        let object = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
        let variables = object["variables"] as! [String: Any]
        let filter = variables["query"] as! String
        if filter.contains("review-requested:") {
            await gate.wait()
            if failRequested { throw URLError(.notConnectedToInternet) }
        }
        let edges = filter.contains("assignee:") ? [edge] : []
        let response = GraphQLSearchResponse(data: ResponseData(search: Search(edges: edges, issueCount: edges.count,
            pageInfo: PageInfo(hasNextPage: false, endCursor: nil))))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(response)
    }
}
