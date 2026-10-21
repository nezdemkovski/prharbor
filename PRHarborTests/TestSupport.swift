import Defaults
import Foundation
import ImageIO
import Security
import SwiftUI
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
        let query = dictionary["query"] as? String
    else {
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
        let value = input[key] as? String
    else {
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

/// Production HTTP transport over a mocked URL session.
nonisolated enum TestGitHubTransport {
    static func client(baseURL: String, buildType: BuildType, session: URLSession = .shared) throws -> GitHubClient {
        try GitHubClient(
            baseURL: baseURL, buildType: buildType,
            transport: GitHubHTTPTransport(apiBaseURL: baseURL, token: "test-token", session: session))
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
        guard let filter = variables["query"] as? String else {
            return try PullFixtureResponse.data(for: body!, edges: [edge])
        }
        if filter.contains("review-requested:") {
            await gate.wait()
            if failRequested { throw URLError(.notConnectedToInternet) }
        }
        return try PullFixtureResponse.data(for: body!, edges: filter.contains("assignee:") ? [edge] : [])
    }
}

/// Answers both refresh phases from full fixtures: a search lists them with their URL as
/// node ID, and a node batch returns the requested ones in full.
nonisolated enum PullFixtureResponse {
    static func data(for body: Data, edges: [Edge], viewer: String? = nil) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func json(_ pull: Pull) throws -> [String: Any] {
            var node = try JSONSerialization.jsonObject(with: encoder.encode(pull)) as! [String: Any]
            node["id"] = pull.url.absoluteString
            return node
        }
        let response: [String: Any]
        if (object["query"] as! String).contains("nodes(ids:") {
            let ids = Set((object["variables"] as! [String: Any])["ids"] as! [String])
            response = ["data": ["nodes": try edges.filter { ids.contains($0.node.url.absoluteString) }.map { try json($0.node) }]]
        } else {
            var data: [String: Any] = ["search": ["pageInfo": ["hasNextPage": false], "nodes": try edges.map { try json($0.node) }]]
            if let viewer { data["viewer"] = ["login": viewer] }
            response = ["data": data]
        }
        return try JSONSerialization.data(withJSONObject: response)
    }
}
