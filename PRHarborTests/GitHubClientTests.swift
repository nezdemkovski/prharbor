import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite(.serialized)
struct GitHubClientTests {
    @Test func repeatedPaginationCursorFailsInsteadOfLooping() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let number = recorder.record(body: requestBody(from: request))
            let cursor = number == 2 ? "second" : "first"
            let body = Data(#"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":true,"endCursor":"\#(cursor)"}}}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { MockURLProtocol.requestHandler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = try TestGitHubTransport.client(baseURL: "https://cursor-cycle.example/api/v3", buildType: .none,
                                     session: URLSession(configuration: configuration))
        await #expect(throws: URLError.self) { try await client.fetchPulls(filter: "author:octocat") }
        #expect(recorder.bodies.count == 3)
    }

    @Test func avatarDownloadsAreSharedAndHTTPFailuresAreNotCached() async throws {
        let recorder = RequestRecorder()
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwTjvzHwAEmgJlc/kGHwAAAABJRU5ErkJggg=="))
        MockURLProtocol.requestHandler = { request in
            let number = recorder.record(body: nil)
            Thread.sleep(forTimeInterval: 0.03)
            return (HTTPURLResponse(url: request.url!, statusCode: number == 1 ? 404 : 200,
                                    httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, png)
        }
        defer { MockURLProtocol.requestHandler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let cache = AvatarImageCache(session: URLSession(configuration: configuration))
        let url = try #require(URL(string: "https://avatars.example/avatar.png"))
        #expect(await cache.image(for: url) == nil)
        async let a = cache.image(for: url)
        async let b = cache.image(for: url)
        async let c = cache.image(for: url)
        let images = await [a, b, c]
        #expect(images.allSatisfy { $0 != nil })
        #expect(await cache.image(for: url) != nil)
        #expect(recorder.bodies.count == 2)
    }

    @Test func resourceLimitRetriesTheSamePageWithFewerResults() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let number = recorder.record(body: requestBody(from: request))
            let data: Data
            if number == 2 {
                data = Data(#"{"errors":[{"message":"Resource limits for this query exceeded."}]}"#.utf8)
            } else {
                let pageInfo = number == 1 ? #"{"hasNextPage":true,"endCursor":"next-page"}"# : #"{"hasNextPage":false,"endCursor":null}"#
                data = Data(#"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":\#(pageInfo)}}}"#.utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { MockURLProtocol.requestHandler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = try TestGitHubTransport.client(baseURL: "https://resource-limit.example.com/api/v3",
                                     buildType: .none, session: URLSession(configuration: configuration))
        #expect(try await client.fetchPulls(filter: "author:octocat").isEmpty)
        #expect(recorder.bodies.count == 3)
        let secondBody = try #require(recorder.bodies[1])
        let retryBody = try #require(recorder.bodies[2])
        let second = try #require(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let retry = try #require(JSONSerialization.jsonObject(with: retryBody) as? [String: Any])
        let secondVariables = try #require(second["variables"] as? [String: Any])
        let retryVariables = try #require(retry["variables"] as? [String: Any])
        #expect(secondVariables["cursor"] as? String == "next-page")
        #expect(retryVariables["cursor"] as? String == "next-page")
        #expect(secondVariables["pageSize"] as? Int == 20)
        #expect(retryVariables["pageSize"] as? Int == 10)
    }

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
        let client = try TestGitHubTransport.client(
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

        #expect(query.contains("first: $pageSize"))
        #expect(firstVariables["pageSize"] as? Int == 20)
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
            _ = try TestGitHubTransport.client(
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
        let client = try TestGitHubTransport.client(
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
        let client = try TestGitHubTransport.client(
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
        return try TestGitHubTransport.client(
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
