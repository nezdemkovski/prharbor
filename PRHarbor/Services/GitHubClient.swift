import Foundation

nonisolated protocol GitHubAPITransport: Sendable {
    func api(_ endpoint: String, body: Data?) async throws -> Data
}

nonisolated struct GitHubClient: Sendable {
    let baseURL: URL
    let buildType: BuildType
    private let transport: any GitHubAPITransport

    init(
        baseURL: String,
        buildType: BuildType,
        transport: any GitHubAPITransport
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
        self.transport = transport
    }

    @concurrent
    func fetchPulls(filter: String) async throws -> [Edge] {
        let queryString = "is:open is:pr \(filter) archived:false"
        let cacheKey = graphQLURL.absoluteString
        let cachedStackSupport = await StackCapabilityCache.shared.value(for: cacheKey)

        if cachedStackSupport == false {
            return try await fetchPullPages(queryString: queryString, includeStacks: false)
        }

        do {
            let edges = try await fetchPullPages(queryString: queryString, includeStacks: true)
            await StackCapabilityCache.shared.set(true, for: cacheKey)
            return edges
        } catch let error as GraphQLAPIError where error.isMissingStackSchema {
            await StackCapabilityCache.shared.set(false, for: cacheKey)
            return try await fetchPullPages(queryString: queryString, includeStacks: false)
        }
    }

    private func fetchPullPages(queryString: String, includeStacks: Bool) async throws -> [Edge] {
        let graphQLQuery = buildGraphQLQuery(includeStacks: includeStacks)
        var edges: [Edge] = []
        var cursor: String?
        var pageSize = 20

        var visitedCursors = Set<String>()
        while true {
            try Task.checkCancellation()
            let response: GraphQLSearchResponse
            do {
                response = try await postGraphQL(
                    query: graphQLQuery,
                    variables: GraphQLVariables(searchQuery: queryString, cursor: cursor, pageSize: pageSize)
                )
            } catch let error as GraphQLAPIError where error.isResourceLimit && pageSize > 1 {
                pageSize = max(1, pageSize / 2)
                continue
            }
            edges.append(contentsOf: response.data.search.edges)

            guard response.data.search.pageInfo.hasNextPage else { break }
            guard let nextCursor = response.data.search.pageInfo.endCursor,
                  nextCursor != cursor, visitedCursors.insert(nextCursor).inserted else {
                throw URLError(.cannotParseResponse)
            }
            cursor = nextCursor
        }

        guard includeStacks else { return edges }
        return try await fetchStackDetails(for: edges)
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
            } catch let error as GitHubCLIError where error == .accountChanged {
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
            throw GraphQLAPIError(messages: errorResponse.errors.map(\.message))
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

    private func buildGraphQLQuery(includeStacks: Bool) -> String {
        let buildFields: String
        let stackFields = includeStacks ? """
        stack {
            id
            number
            baseRefName
            size
        }
        stackEntry {
            position
        }
        """ : ""

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
                                totalCount
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
        query PullRequests($query: String!, $cursor: String, $pageSize: Int!) {
            search(query: $query, type: ISSUE, first: $pageSize, after: $cursor) {
                issueCount
                pageInfo {
                    hasNextPage
                    endCursor
                }
                edges {
                    node {
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
                            deletions
                            additions
                            isDraft
                            isReadByViewer
                            reviewDecision
                            mergeable
                            \(stackFields)
                            author {
                                login
                                avatarUrl
                            }
                            repository {
                                name
                                nameWithOwner
                            }
                            labels(first: 5) {
                                nodes {
                                    name
                                    color
                                }
                            }
                            reviews(states: APPROVED, first: 10) {
                                totalCount
                                edges {
                                    node {
                                        author {
                                            login
                                        }
                                    }
                                }
                            }
                            \(buildFields)
                        }
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

private nonisolated struct GraphQLError: Decodable, Sendable {
    let message: String
}

private nonisolated struct GraphQLAPIError: LocalizedError, Sendable {
    let messages: [String]

    var errorDescription: String? {
        var seen: Set<String> = []
        return messages.filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    var isResourceLimit: Bool {
        messages.contains { $0.lowercased().contains("resource limits for this query exceeded") }
    }

    var isMissingStackSchema: Bool {
        messages.contains { message in
            let lowercased = message.lowercased()
            return lowercased.contains("stack")
                && (lowercased.contains("field") || lowercased.contains("type"))
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
        let updatePullRequestBranch: Payload
    }

    struct Payload: Decodable, Sendable {
        let pullRequest: UpdatedPullRequest
    }

    struct UpdatedPullRequest: Decodable, Sendable {
        let id: String
        let headRefOid: String
    }
}
