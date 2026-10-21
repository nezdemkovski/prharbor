import Foundation
import os

nonisolated protocol GitHubAPITransport: Sendable {
    func api(_ endpoint: String, body: Data?) async throws -> Data
}

nonisolated struct GitHubClient: Sendable {
    let baseURL: URL
    let buildType: BuildType
    /// When set, every search page and mutation must be answered by this account.
    let expectedLogin: String?
    private let transport: any GitHubAPITransport

    init(
        baseURL: String,
        buildType: BuildType,
        transport: any GitHubAPITransport,
        expectedLogin: String? = nil
    ) throws {
        guard let url = URL(string: baseURL),
              url.scheme == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            throw URLError(.badURL)
        }

        self.baseURL = url
        self.buildType = buildType
        self.expectedLogin = expectedLogin
        self.transport = transport
    }

    /// Lists the open pull requests matching `filter` in two phases: a cheap search for
    /// identity and change markers, then full details only for pull requests that are new
    /// or changed compared with `known`, fetched in parallel batches.
    @concurrent
    func fetchPulls(filter: String, known: [URL: Pull] = [:]) async throws -> [Edge] {
        let queryString = "is:open is:pr \(filter) archived:false"
        let cacheKey = graphQLURL.absoluteString
        let cachedStackSupport = await StackCapabilityCache.shared.value(for: cacheKey)

        if cachedStackSupport == false {
            return try await fetchPullPages(queryString: queryString, includeStacks: false, known: known)
        }

        do {
            let edges = try await fetchPullPages(queryString: queryString, includeStacks: true, known: known)
            await StackCapabilityCache.shared.set(true, for: cacheKey)
            return edges
        } catch let error as GraphQLAPIError where error.isMissingStackSchema {
            await StackCapabilityCache.shared.set(false, for: cacheKey)
            return try await fetchPullPages(queryString: queryString, includeStacks: false, known: known)
        }
    }

    private func fetchPullPages(queryString: String, includeStacks: Bool, known: [URL: Pull]) async throws -> [Edge] {
        let started = ContinuousClock.now
        let summaries = try await fetchSummaries(queryString: queryString, includeStacks: includeStacks)
        let stale = summaries.filter { summary in known[summary.url].map { !isCurrent($0, summary) } ?? true }
        let details = try await fetchDetails(ids: stale.map(\.id))
        let edges = summaries.compactMap { summary -> Edge? in
            // A pull request hidden from the token since the search returns no details; skip it.
            guard var pull = details[summary.url] ?? known[summary.url] else { return nil }
            pull.updatedAt = summary.updatedAt
            pull.isDraft = summary.isDraft
            pull.mergeable = summary.mergeable
            pull.stack = summary.stack
            pull.stackEntry = summary.stackEntry
            return Edge(node: pull)
        }
        syncLog.notice("Pulls \(Self.kind(of: queryString), privacy: .public): \(summaries.count) listed, \(stale.count) new or changed, in \(started.duration(to: .now), privacy: .public)")
        guard includeStacks else { return edges }
        return try await fetchStackDetails(for: edges)
    }

    /// Phase one: every page of the search with only identity and change markers.
    private func fetchSummaries(queryString: String, includeStacks: Bool) async throws -> [PullSummary] {
        let graphQLQuery = buildSummaryQuery(includeStacks: includeStacks)
        var summaries: [PullSummary] = []
        var cursor: String?
        var pageSize = 100
        var visitedCursors = Set<String>()
        while true {
            try Task.checkCancellation()
            let response: GraphQLSummaryResponse
            let started = ContinuousClock.now
            do {
                response = try await postGraphQL(
                    query: graphQLQuery,
                    variables: GraphQLVariables(searchQuery: queryString, cursor: cursor, pageSize: pageSize)
                )
            } catch let error as GraphQLAPIError where error.isResourceLimit && pageSize > 1 {
                pageSize = max(1, pageSize / 2)
                continue
            }
            try verifyAccount(response.data.viewer?.login)
            summaries.append(contentsOf: response.data.search.nodes)
            syncLog.notice("Search \(Self.kind(of: queryString), privacy: .public) page \(visitedCursors.count + 1): \(response.data.search.nodes.count) PRs of page size \(pageSize), stacks \(includeStacks), in \(started.duration(to: .now), privacy: .public)")

            guard response.data.search.pageInfo.hasNextPage else { break }
            guard let nextCursor = response.data.search.pageInfo.endCursor,
                  nextCursor != cursor, visitedCursors.insert(nextCursor).inserted else {
                throw URLError(.cannotParseResponse)
            }
            cursor = nextCursor
        }
        return summaries
    }

    /// Cached details stay valid while every change marker the search reports still matches.
    /// Pushes, comments, reviews and review requests all move `updatedAt`; finished checks and
    /// base branch changes do not, so CI state and mergeability are compared directly.
    private func isCurrent(_ pull: Pull, _ summary: PullSummary) -> Bool {
        pull.updatedAt == summary.updatedAt && pull.isDraft == summary.isDraft && pull.mergeable == summary.mergeable
            && (buildType == .none || pull.commits?.nodes.first?.commit.statusCheckRollup?.state == summary.ciState)
    }

    static let detailBatchSize = 10
    static let maximumConcurrentDetailRequests = 4

    /// Phase two: full details in batches, a few requests at a time. Unlike search pages,
    /// node batches do not depend on each other.
    private func fetchDetails(ids: [String]) async throws -> [URL: Pull] {
        let batches = stride(from: 0, to: ids.count, by: Self.detailBatchSize).map {
            Array(ids[$0..<min($0 + Self.detailBatchSize, ids.count)])
        }
        guard !batches.isEmpty else { return [:] }
        return try await withThrowingTaskGroup(of: [Pull].self) { group in
            var next = 0
            while next < min(Self.maximumConcurrentDetailRequests, batches.count) {
                let batch = batches[next]
                group.addTask { try await self.fetchDetailBatch(batch) }
                next += 1
            }
            var details: [URL: Pull] = [:]
            while let pulls = try await group.next() {
                for pull in pulls { details[pull.url] = pull }
                if next < batches.count {
                    let batch = batches[next]
                    group.addTask { try await self.fetchDetailBatch(batch) }
                    next += 1
                }
            }
            return details
        }
    }

    private func fetchDetailBatch(_ ids: [String]) async throws -> [Pull] {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        do {
            let response: GraphQLDetailsResponse = try await postGraphQL(
                query: buildDetailsQuery(), variables: GraphQLStackVariables(ids: ids))
            syncLog.notice("Details for \(ids.count) PRs in \(started.duration(to: .now), privacy: .public)")
            return response.data.nodes
        } catch let error as GraphQLAPIError where error.isResourceLimit && ids.count > 1 {
            async let first = fetchDetailBatch(Array(ids.prefix(ids.count / 2)))
            async let second = fetchDetailBatch(Array(ids.dropFirst(ids.count / 2)))
            return try await first + second
        }
    }

    private static func kind(of queryString: String) -> Substring {
        queryString.split(separator: " ").first { $0.contains(":") && !$0.hasPrefix("is:") }?.split(separator: ":").first ?? "search"
    }

    private func fetchStackDetails(for edges: [Edge]) async throws -> [Edge] {
        let stackIDs = Array(Set(edges.compactMap { $0.node.stack?.id })).sorted()
        guard !stackIDs.isEmpty else { return edges }

        var stacksByID: [String: PullRequestStack] = [:]
        for startIndex in stride(from: 0, to: stackIDs.count, by: 100) {
            let endIndex = min(startIndex + 100, stackIDs.count)
            let response: GraphQLStackResponse = try await postGraphQL(
                query: buildStackDetailsQuery(),
                variables: GraphQLStackVariables(ids: Array(stackIDs[startIndex..<endIndex]))
            )
            for stack in response.data.nodes.compactMap({ $0 }) {
                stacksByID[stack.id] = stack
            }
        }

        return edges.map { edge in
            var enriched = edge
            if let stackID = edge.node.stack?.id, let stack = stacksByID[stackID] {
                enriched.node.stack = stack
            }
            return enriched
        }
    }

    @concurrent
    func rebaseStack(_ stack: PullRequestStack) async throws -> StackRebaseResult {
        let entries = stack.entries?.nodes ?? []
        guard entries.count >= stack.size else {
            throw StackRebaseError.incompleteStack(expected: stack.size, available: entries.count)
        }

        let openEntries = entries
            .filter { $0.pullRequest?.state == "OPEN" }
            .sorted { $0.position < $1.position }
        guard !openEntries.isEmpty else {
            throw StackRebaseError.noOpenPullRequests
        }

        if let conflicting = openEntries.compactMap(\.pullRequest).first(where: { $0.mergeable == "CONFLICTING" }) {
            throw StackRebaseError.conflictingBranch(conflicting.headRefName)
        }

        let mutation = """
        mutation RebasePullRequestBranch($input: UpdatePullRequestBranchInput!) {
            updatePullRequestBranch(input: $input) {
                pullRequest {
                    id
                    headRefOid
                }
            }
        }
        """

        var completed = 0
        for entry in openEntries {
            try Task.checkCancellation()
            guard let pullRequest = entry.pullRequest else { continue }
            do {
                let _: GraphQLRebaseResponse = try await postGraphQL(
                    query: mutation,
                    variables: GraphQLRebaseVariables(input: .init(
                        pullRequestId: pullRequest.id,
                        expectedHeadOid: pullRequest.headRefOid,
                        updateMethod: "REBASE"
                    ))
                )
                completed += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as GitHubAccessError where error == .accountChanged {
                // Keep account mismatch identifiable so the store can invalidate
                // its old identity rather than treating it as ordinary partial progress.
                throw error
            } catch {
                throw StackRebaseError.partial(
                    completed: completed,
                    total: openEntries.count,
                    failedBranch: pullRequest.headRefName,
                    reason: error.localizedDescription
                )
            }
        }

        return StackRebaseResult(rebasedCount: completed, totalCount: openEntries.count)
    }

    @concurrent
    func fetchUser() async throws -> User {
        let data = try await transport.api("user", body: nil)
        return try JSONDecoder().decode(User.self, from: data)
    }

    private func verifyAccount(_ login: String?) throws {
        guard let expectedLogin, login != expectedLogin else { return }
        throw GitHubAccessError.accountChanged
    }

    private func postGraphQL<T: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables
    ) async throws -> T {
        let body = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let data = try await transport.api("graphql", body: body)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let errorResponse = try? decoder.decode(GraphQLErrorResponse.self, from: data),
           !errorResponse.errors.isEmpty {
            throw GraphQLAPIError(errors: errorResponse.errors)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private var graphQLURL: URL {
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedPath.hasSuffix("api/v3") else {
            return endpoint("graphql")
        }

        return baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("graphql")
    }

    private func buildDetailsQuery() -> String {
        let buildFields: String

        switch buildType {
        case .checks:
            buildFields = """
        commits(last: 1) {
            nodes {
                commit {
                    statusCheckRollup { state }
                    checkSuites(first: 10) {
                        nodes {
                            app {
                                name
                            }
                            checkRuns(first: 10) {
                                nodes {
                                    name
                                    conclusion
                                    detailsUrl
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        case .commitStatus:
            buildFields = """
        commits(last: 1) {
            nodes {
                commit {
                    statusCheckRollup {
                        state
                        contexts(first: 20) {
                            nodes {
                                ... on StatusContext {
                                    context
                                    description
                                    state
                                    targetUrl
                                }
                                ... on CheckRun {
                                    name
                                    conclusion
                                    detailsUrl
                                    title
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        case .none:
            buildFields = ""
        }

        return """
        query PullRequestDetails($ids: [ID!]!) {
            nodes(ids: $ids) {
                ... on PullRequest {
                    number
                    createdAt
                    updatedAt
                    title
                    headRefName
                    baseRefName
                    timelineItems(last: 60, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_COMMIT, PULL_REQUEST_REVIEW, REVIEW_REQUESTED_EVENT]) {
                        pageInfo { hasPreviousPage }
                        nodes {
                            __typename
                            ... on IssueComment { createdAt author { login avatarUrl } }
                            ... on PullRequestCommit { commit { committedDate } }
                            ... on PullRequestReview { submittedAt state author { login avatarUrl } }
                            ... on ReviewRequestedEvent {
                                createdAt
                                requestedReviewer {
                                    __typename
                                    ... on User { login avatarUrl }
                                }
                            }
                        }
                    }
                    reviewRequests(first: 30) {
                        nodes {
                            requestedReviewer {
                                __typename
                                ... on User { login avatarUrl }
                            }
                        }
                    }
                    url
                    isDraft
                    reviewDecision
                    mergeable
                    author {
                        login
                        avatarUrl
                    }
                    repository {
                        name
                        nameWithOwner
                    }
                    \(buildFields)
                }
            }
        }
        """
    }

    /// Identity and the change markers `isCurrent` compares, without history or check details.
    private func buildSummaryQuery(includeStacks: Bool) -> String {
        let stackFields = includeStacks ? "stack { id number baseRefName size }\n stackEntry { position }" : ""
        let ciFields = buildType == .none ? "" : "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }"
        return """
        query PullRequestSummaries($query: String!, $cursor: String, $pageSize: Int!) {
            viewer { login }
            search(query: $query, type: ISSUE, first: $pageSize, after: $cursor) {
                pageInfo {
                    hasNextPage
                    endCursor
                }
                nodes {
                    ... on PullRequest {
                        id
                        url
                        updatedAt
                        isDraft
                        mergeable
                        \(stackFields)
                        \(ciFields)
                    }
                }
            }
        }
        """
    }

    private func buildStackDetailsQuery() -> String {
        """
        query PullRequestStacks($ids: [ID!]!) {
            nodes(ids: $ids) {
                ... on PullRequestStack {
                    id
                    number
                    baseRefName
                    size
                    entries(first: 100) {
                        nodes {
                            position
                            pullRequest {
                                id
                                number
                                title
                                url
                                state
                                isDraft
                                headRefName
                                headRefOid
                                reviewDecision
                                mergeable
                            }
                        }
                    }
                }
            }
        }
        """
    }
}

private nonisolated struct GraphQLErrorResponse: Decodable, Sendable {
    let errors: [GraphQLError]
}

nonisolated struct GraphQLError: Decodable, Sendable {
    let message: String
    var type: String?
    var extensions: Extensions?

    /// Query validation errors identify the missing schema element; execution errors have a `type`.
    struct Extensions: Decodable, Sendable {
        var code: String?
        var typeName: String?
        var fieldName: String?
    }
}

nonisolated struct GraphQLAPIError: LocalizedError, Sendable {
    let errors: [GraphQLError]

    var errorDescription: String? {
        var seen: Set<String> = []
        return errors.map(\.message).filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    var isResourceLimit: Bool {
        errors.contains { $0.type == "RESOURCE_LIMITS_EXCEEDED" }
    }

    /// GitHub Enterprise versions without stacks reject the `stack` fields or the stack type.
    var isMissingStackSchema: Bool {
        errors.contains { error in
            guard let extensions = error.extensions,
                  extensions.code == "undefinedField" || extensions.code == "undefinedType" else { return false }
            return [extensions.fieldName, extensions.typeName].contains { $0?.lowercased().contains("stack") == true }
        }
    }
}

private actor StackCapabilityCache {
    static let shared = StackCapabilityCache()

    private var values: [String: Bool] = [:]

    func value(for key: String) -> Bool? {
        values[key]
    }

    func set(_ value: Bool, for key: String) {
        values[key] = value
    }
}

private nonisolated struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

nonisolated struct GraphQLVariables: Encodable, Sendable {
    let searchQuery: String
    let cursor: String?
    var pageSize: Int = 20

    enum CodingKeys: String, CodingKey {
        case searchQuery = "query"
        case cursor
        case pageSize
    }
}

private nonisolated struct GraphQLStackVariables: Encodable, Sendable {
    let ids: [String]
}

private nonisolated struct GraphQLRebaseVariables: Encodable, Sendable {
    let input: Input

    struct Input: Encodable, Sendable {
        let pullRequestId: String
        let expectedHeadOid: String
        let updateMethod: String
    }
}

private nonisolated struct GraphQLRebaseResponse: Decodable, Sendable {
    let data: Data

    struct Data: Decodable, Sendable {
        let updatePullRequestBranch: Payload?
    }

    struct Payload: Decodable, Sendable {
        let pullRequest: UpdatedPullRequest?
    }

    struct UpdatedPullRequest: Decodable, Sendable {
        let id: String
        let headRefOid: String
    }
}
