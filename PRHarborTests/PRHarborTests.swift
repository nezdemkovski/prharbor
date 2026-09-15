import Foundation
import Testing
@testable import PRHarbor

@Suite(.serialized)
struct GitHubClientTests {
    @Test
    func paginatesUntilGitHubReportsTheLastPage() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let requestNumber = recorder.record(body: requestBody(from: request))
            let pageInfo: String

            if requestNumber == 1 {
                pageInfo = #"{"hasNextPage":true,"endCursor":"next-page"}"#
            } else {
                pageInfo = #"{"hasNextPage":false,"endCursor":null}"#
            }

            let data = Data(
                #"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":\#(pageInfo)}}}"#.utf8
            )
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try GitHubClient(
            token: "test-token",
            baseURL: "https://api.github.com",
            buildType: .none,
            session: session
        )

        let pulls = try await client.fetchPulls(filter: "author:octocat")

        #expect(pulls.isEmpty)
        #expect(recorder.bodies.count == 2)

        let firstBody = try #require(recorder.bodies[0])
        let secondBody = try #require(recorder.bodies[1])
        let firstJSON = try #require(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let secondJSON = try #require(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let firstVariables = try #require(firstJSON["variables"] as? [String: Any])
        let secondVariables = try #require(secondJSON["variables"] as? [String: Any])
        let query = try #require(firstJSON["query"] as? String)

        #expect(query.contains("first: 100"))
        #expect(query.contains("pageInfo"))
        #expect(firstVariables["query"] as? String == "is:open is:pr author:octocat archived:false")
        #expect(firstVariables["cursor"] == nil)
        #expect(secondVariables["cursor"] as? String == "next-page")
    }

    @Test
    func rejectsInsecureAPIURLs() {
        #expect(throws: URLError.self) {
            _ = try GitHubClient(
                token: "test-token",
                baseURL: "http://github.example.com/api/v3",
                buildType: .none
            )
        }
    }
}

struct GitHubConstantsTests {
    @Test
    func buildsGitHubDotComDeviceURLs() throws {
        #expect(
            try GitHubConstants.deviceCodeUrl(baseUrl: "https://api.github.com").absoluteString
                == "https://github.com/login/device/code"
        )
    }

    @Test
    func buildsEnterpriseDeviceURLs() throws {
        #expect(
            try GitHubConstants.tokenUrl(baseUrl: "https://github.example.com/api/v3").absoluteString
                == "https://github.example.com/login/oauth/access_token"
        )
    }

    @Test
    func rejectsEnterpriseURLsWithoutTheAPISuffix() {
        #expect(throws: URLError.self) {
            _ = try GitHubConstants.tokenUrl(baseUrl: "https://github.example.com")
        }
    }
}

struct CICheckTests {
    @Test
    func doesNotReuseChecksFromAnotherPullRequest() throws {
        let firstURL = try #require(URL(string: "https://github.com/checks/first"))
        let secondURL = try #require(URL(string: "https://github.com/checks/second"))
        let first = commits(checkName: "build", conclusion: "SUCCESS", url: firstURL)
        let second = commits(checkName: "build", conclusion: "FAILURE", url: secondURL)

        #expect(CICheck.from(commits: first) == [
            CICheck(name: "build", status: "SUCCESS", url: firstURL, index: 0)
        ])
        #expect(CICheck.from(commits: second) == [
            CICheck(name: "build", status: "FAILURE", url: secondURL, index: 0)
        ])
    }

    @Test(arguments: ["FAILURE", "ERROR", "CANCELLED", "STALE", "STARTUP_FAILURE", "TIMED_OUT"])
    func recognizesFailureStates(_ status: String) {
        #expect(ciStatusKind(status) == .failure)
    }

    private func commits(checkName: String, conclusion: String, url: URL) -> CommitsNodes {
        CommitsNodes(nodes: [
            Commit(commit: CheckSuites(
                checkSuites: CheckSuitsNodes(nodes: [
                    CheckSuit(
                        app: nil,
                        checkRuns: CheckRun(
                            totalCount: 1,
                            nodes: [Check(name: checkName, conclusion: conclusion, detailsUrl: url)]
                        )
                    )
                ]),
                statusCheckRollup: nil
            ))
        ])
    }
}

struct PullRefreshTrackerTests {
    @Test
    func reenabledCategoryEstablishesABaselineBeforeNotifying() throws {
        var tracker = PullRefreshTracker()
        let first = Edge(node: try pull(number: 1))
        let second = Edge(node: try pull(number: 2))
        let third = Edge(node: try pull(number: 3))

        #expect(tracker.update(edges: [first], fetched: true, canNotify: false).isEmpty)
        #expect(tracker.update(edges: [], fetched: false, canNotify: true).isEmpty)
        #expect(tracker.update(edges: [first, second], fetched: true, canNotify: true).isEmpty)
        #expect(tracker.update(edges: [first, second, third], fetched: true, canNotify: true) == [third.node])
    }

    private func pull(number: Int) throws -> Pull {
        Pull(
            url: try #require(URL(string: "https://github.com/example/repo/pull/\(number)")),
            updatedAt: .now,
            createdAt: .now,
            title: "PR \(number)",
            number: number,
            deletions: nil,
            additions: nil,
            reviews: Review(totalCount: 0, edges: []),
            author: nil,
            repository: Repository(name: "repo", nameWithOwner: "example/repo"),
            commits: nil,
            labels: Nodes(nodes: []),
            headRefName: "feature/\(number)",
            isDraft: false,
            isReadByViewer: false,
            reviewDecision: nil,
            mergeable: nil
        )
    }
}

private nonisolated final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var bodies: [Data?] = []

    func record(body: Data?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        bodies.append(body)
        return bodies.count
    }
}

private nonisolated func requestBody(from request: URLRequest) -> Data? {
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

private nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
