import Foundation
import Testing
@testable import PRHarbor

/// Collects every GraphQL document the client can send. Scripts/validate-graphql.sh exports
/// them through PRHARBOR_GRAPHQL_EXPORT and validates them against GitHub's schema.
@Suite("GraphQL documents")
struct GraphQLDocumentTests {
    @Test @MainActor func everyDocumentVariantIsCollected() async throws {
        var stacked = try #require(TimelinePreviewData.items(now: .now).first { $0.pull.stack != nil }).pull
        stacked.stack?.entries = nil
        let edges = [Edge(node: stacked)]
        var documents: [String: String] = [:]
        for buildType in BuildType.allCases {
            for includeStacks in [true, false] {
                let transport = DocumentRecorder(edges: edges, rejectStacks: !includeStacks)
                let client = try GitHubClient(baseURL: "https://\(buildType.rawValue)-\(includeStacks).example/api/v3",
                                              buildType: buildType, transport: transport)
                _ = try await client.fetchPulls(filter: "author:octocat")
                documents.merge(await transport.documents) { first, _ in first }
            }
        }
        let rebase = DocumentRecorder(edges: [])
        let stack = PullRequestStack(id: "S", number: 1, baseRefName: "main", size: 1, entries: .init(nodes: [
            .init(position: 1, pullRequest: .init(id: "PR_1", number: 1, title: "One", url: URL(string: "https://github.com/o/r/pull/1")!,
                state: "OPEN", isDraft: false, headRefName: "one", headRefOid: "oid", reviewDecision: nil, mergeable: "MERGEABLE"))]))
        _ = try await GitHubClient(baseURL: "https://api.github.com", buildType: .none, transport: rebase).rebaseStack(stack)
        documents.merge(await rebase.documents) { first, _ in first }

        // Summaries and details per check mode, with and without stacks, plus stacks and rebase.
        let names = Set(documents.values.compactMap { $0.split(separator: "(").first?.split(separator: " ").last })
        #expect(names == ["PullRequestSummaries", "PullRequestDetails", "PullRequestStacks", "RebasePullRequestBranch"])
        #expect(documents.count == 2 + 2 + BuildType.allCases.count + 1 + 1)

        guard let directory = ProcessInfo.processInfo.environment["PRHARBOR_GRAPHQL_EXPORT"] else { return }
        for (index, document) in documents.values.sorted().enumerated() {
            try document.write(toFile: "\(directory)/document-\(index).graphql", atomically: true, encoding: .utf8)
        }
    }
}

/// Answers both refresh phases and the stack query; with `rejectStacks`, behaves like a
/// GitHub Enterprise schema without stack fields. Records each distinct document.
private actor DocumentRecorder: GitHubAPITransport {
    let edges: [Edge]
    let rejectStacks: Bool
    private(set) var documents: [String: String] = [:]
    init(edges: [Edge], rejectStacks: Bool = false) { self.edges = edges; self.rejectStacks = rejectStacks }

    func api(_ endpoint: String, body: Data?) async throws -> Data {
        let object = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
        let query = object["query"] as! String
        documents[query] = query
        if rejectStacks && query.contains("stack {") {
            return Data(#"{"errors":[{"message":"Field 'stack' doesn't exist on type 'PullRequest'","extensions":{"code":"undefinedField","typeName":"PullRequest","fieldName":"stack"}}]}"#.utf8)
        }
        if query.contains("PullRequestStacks") { return Data(#"{"data":{"nodes":[]}}"#.utf8) }
        if query.contains("mutation") { return Data(#"{"data":{"updatePullRequestBranch":{"pullRequest":{"id":"PR_1","headRefOid":"new"}}}}"#.utf8) }
        return try PullFixtureResponse.data(for: body!, edges: edges)
    }
}
