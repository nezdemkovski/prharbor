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
        #expect(query.contains("stack {"))
        #expect(query.contains("stackEntry {"))
        #expect(!query.contains("entries(first: 100)"))
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

    @Test
    func retriesWithoutStacksWhenTheServerSchemaIsOlder() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let requestNumber = recorder.record(body: requestBody(from: request))
            let data: Data

            if requestNumber == 1 {
                data = Data(#"{"errors":[{"message":"Field 'stack' doesn't exist on type 'PullRequest'"}]}"#.utf8)
            } else {
                data = Data(
                    #"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8
                )
            }

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
            baseURL: "https://fallback.example.com/api/v3",
            buildType: .none,
            session: session
        )

        let pulls = try await client.fetchPulls(filter: "author:octocat")

        #expect(pulls.isEmpty)
        #expect(recorder.bodies.count == 2)
        let firstQuery = try query(from: #require(recorder.bodies[0]))
        let fallbackQuery = try query(from: #require(recorder.bodies[1]))
        #expect(firstQuery.contains("stack {"))
        #expect(!fallbackQuery.contains("stack {"))
    }

    @Test
    func fetchesEachStackMapInASeparateBatch() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let requestNumber = recorder.record(body: requestBody(from: request))
            let query = try query(from: #require(requestBody(from: request)))
            let data: Data

            if query.contains("query PullRequestStacks") {
                data = Data(#"{"data":{"nodes":[{"id":"PRS_example","number":42,"baseRefName":"main","size":2,"entries":{"nodes":[{"position":1,"pullRequest":{"id":"PR_101","number":101,"title":"Foundation","url":"https://github.com/example/repo/pull/101","state":"OPEN","isDraft":false,"headRefName":"stack/foundation","headRefOid":"oid-101","reviewDecision":"APPROVED","mergeable":"MERGEABLE"}},{"position":2,"pullRequest":{"id":"PR_102","number":102,"title":"UI","url":"https://github.com/example/repo/pull/102","state":"OPEN","isDraft":true,"headRefName":"stack/ui","headRefOid":"oid-102","reviewDecision":null,"mergeable":"UNKNOWN"}}]}}]}}"#.utf8)
            } else {
                data = Data(#"{"data":{"search":{"edges":[{"node":{"number":102,"createdAt":"2026-09-16T00:00:00Z","updatedAt":"2026-09-16T00:00:00Z","title":"UI","headRefName":"stack/ui","url":"https://github.com/example/repo/pull/102","deletions":1,"additions":2,"isDraft":true,"isReadByViewer":false,"reviewDecision":null,"mergeable":"UNKNOWN","stack":{"id":"PRS_example","number":42,"baseRefName":"main","size":2},"stackEntry":{"position":2},"author":{"login":"octocat","avatarUrl":null},"repository":{"name":"repo","nameWithOwner":"example/repo"},"labels":{"nodes":[]},"reviews":{"totalCount":0,"edges":[]}}}],"issueCount":1,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            #expect(requestNumber <= 2)
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try GitHubClient(
            token: "test-token",
            baseURL: "https://stacks.example.com/api/v3",
            buildType: .none,
            session: session
        )

        let pulls = try await client.fetchPulls(filter: "author:octocat")

        let pull = try #require(pulls.first?.node)
        #expect(recorder.bodies.count == 2)
        #expect(pull.stackEntry?.position == 2)
        #expect(pull.stack?.entries?.nodes.count == 2)
        #expect(pull.stack?.entries?.nodes.last?.pullRequest?.title == "UI")
    }

    @Test
    func rebasesAStackFromTheBaseUpward() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let body = try #require(requestBody(from: request))
            _ = recorder.record(body: body)
            let pullRequestID = try rebasePullRequestID(from: body)
            let data = Data(
                #"{"data":{"updatePullRequestBranch":{"pullRequest":{"id":"\#(pullRequestID)","headRefOid":"updated-\#(pullRequestID)"}}}}"#.utf8
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

        let client = try testClient()
        let result = try await client.rebaseStack(try testStack())

        #expect(result == StackRebaseResult(rebasedCount: 3, totalCount: 3))
        let bodies = recorder.bodies.compactMap { $0 }
        #expect(try bodies.map(rebasePullRequestID(from:)) == ["PR_1", "PR_2", "PR_3"])
        #expect(try bodies.allSatisfy { try rebaseInputValue("updateMethod", from: $0) == "REBASE" })
    }

    @Test
    func refusesAStackWithKnownConflictsBeforeChangingBranches() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            _ = recorder.record(body: requestBody(from: request))
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.requestHandler = nil }

        do {
            _ = try await testClient().rebaseStack(try testStack(conflictingPosition: 2))
            Issue.record("Expected the conflict preflight to fail")
        } catch let error as StackRebaseError {
            #expect(error == .conflictingBranch("stack/2"))
        }
        #expect(recorder.bodies.isEmpty)
    }

    @Test
    func reportsHowFarAStackRebaseGotBeforeAFailure() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let requestNumber = recorder.record(body: requestBody(from: request))
            let data: Data
            if requestNumber == 2 {
                data = Data(#"{"errors":[{"message":"Branch has conflicts"}]}"#.utf8)
            } else {
                let body = try #require(requestBody(from: request))
                let pullRequestID = try rebasePullRequestID(from: body)
                data = Data(
                    #"{"data":{"updatePullRequestBranch":{"pullRequest":{"id":"\#(pullRequestID)","headRefOid":"updated"}}}}"#.utf8
                )
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        do {
            _ = try await testClient().rebaseStack(try testStack())
            Issue.record("Expected the second layer to fail")
        } catch let error as StackRebaseError {
            guard case .partial(let completed, let total, let branch, let reason) = error else {
                Issue.record("Expected a partial stack rebase error")
                return
            }
            #expect(completed == 1)
            #expect(total == 3)
            #expect(branch == "stack/2")
            #expect(reason == "Branch has conflicts")
        }
        #expect(recorder.bodies.count == 2)
    }

    private func testClient() throws -> GitHubClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return try GitHubClient(
            token: "test-token",
            baseURL: "https://rebase.example.com/api/v3",
            buildType: .none,
            session: URLSession(configuration: configuration)
        )
    }

    private func testStack(conflictingPosition: Int? = nil) throws -> PullRequestStack {
        let entries = try [3, 1, 2].map { position in
            PullRequestStackEntry(
                position: position,
                pullRequest: StackedPullRequest(
                    id: "PR_\(position)",
                    number: 100 + position,
                    title: "Layer \(position)",
                    url: try #require(URL(string: "https://github.com/example/repo/pull/\(100 + position)")),
                    state: "OPEN",
                    isDraft: false,
                    headRefName: "stack/\(position)",
                    headRefOid: "oid-\(position)",
                    reviewDecision: nil,
                    mergeable: conflictingPosition == position ? "CONFLICTING" : "MERGEABLE"
                )
            )
        }
        return PullRequestStack(
            id: "PRS_example",
            number: 42,
            baseRefName: "main",
            size: entries.count,
            entries: PullRequestStackEntries(nodes: entries)
        )
    }
}

struct PullRequestStackTests {
    @Test
    func decodesLayerOrderAndTrunk() throws {
        let data = Data(#"""
        {
            "id":"PRS_example",
            "number":42,
            "baseRefName":"main",
            "size":2,
            "entries":{"nodes":[
                {"position":1,"pullRequest":{"id":"PR_101","number":101,"title":"Foundation","url":"https://github.com/example/repo/pull/101","state":"OPEN","isDraft":false,"headRefName":"stack/foundation","headRefOid":"oid-101","reviewDecision":"APPROVED","mergeable":"MERGEABLE"}},
                {"position":2,"pullRequest":{"id":"PR_102","number":102,"title":"UI","url":"https://github.com/example/repo/pull/102","state":"OPEN","isDraft":true,"headRefName":"stack/ui","headRefOid":"oid-102","reviewDecision":null,"mergeable":"UNKNOWN"}}
            ]}
        }
        """#.utf8)

        let stack = try JSONDecoder().decode(PullRequestStack.self, from: data)

        #expect(stack.number == 42)
        #expect(stack.baseRefName == "main")
        #expect(stack.size == 2)
        let entries = try #require(stack.entries?.nodes)
        #expect(entries.map(\.position) == [1, 2])
        #expect(entries[1].pullRequest?.isDraft == true)
    }

    @Test
    func groupsAStackAtItsFirstSortedOccurrenceAndOrdersItsLayers() throws {
        let stack = PullRequestStack(
            id: "PRS_example",
            number: 42,
            baseRefName: "main",
            size: 5
        )
        let shuffledPositions = [5, 2, 4, 1, 3]
        let stackEdges = try shuffledPositions.map { position in
            try edge(number: 100 + position, stack: stack, position: position)
        }
        let standalone = try edge(number: 200)

        let groups = groupPullsForDisplay([stackEdges[0], standalone] + stackEdges.dropFirst())

        #expect(groups.count == 2)
        #expect(groups[0].id == stack.id)
        #expect(groups[0].edges.compactMap(\.node.stackEntry?.position) == [5, 4, 3, 2, 1])
        #expect(groups[1].edges.first?.node.number == 200)
    }

    private func edge(
        number: Int,
        stack: PullRequestStack? = nil,
        position: Int? = nil
    ) throws -> Edge {
        var pull = Pull(
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
        pull.stack = stack
        pull.stackEntry = position.map { PullRequestStackPosition(position: $0) }
        return Edge(node: pull)
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

    @Test
    func summarizesChecksWithoutRenderingEveryCheckInline() {
        let success = CICheck(name: "build", status: "SUCCESS", url: nil, index: 0)
        let skipped = CICheck(name: "optional", status: "SKIPPED", url: nil, index: 1)
        let pending = CICheck(name: "test", status: "IN_PROGRESS", url: nil, index: 2)
        let failure = CICheck(name: "lint", status: "FAILURE", url: nil, index: 3)

        #expect(ciSummaryStatus([]) == nil)
        #expect(ciSummaryStatus([success, skipped]) == .success)
        #expect(ciSummaryStatus([success, pending]) == .pending)
        #expect(ciSummaryStatus([success, pending, failure]) == .failure)
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

private nonisolated func query(from body: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = object as? [String: Any],
          let query = dictionary["query"] as? String else {
        throw URLError(.cannotParseResponse)
    }
    return query
}

private nonisolated func rebasePullRequestID(from body: Data) throws -> String {
    try rebaseInputValue("pullRequestId", from: body)
}

private nonisolated func rebaseInputValue(_ key: String, from body: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = object as? [String: Any],
          let variables = dictionary["variables"] as? [String: Any],
          let input = variables["input"] as? [String: Any],
          let value = input[key] as? String else {
        throw URLError(.cannotParseResponse)
    }
    return value
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
