import Foundation

nonisolated struct GitHubClient: Sendable {
    let token: String
    let baseURL: URL
    let buildType: BuildType
    let session: URLSession

    init(
        token: String,
        baseURL: String,
        buildType: BuildType,
        session: URLSession = .shared
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

        self.token = token
        self.baseURL = url
        self.buildType = buildType
        self.session = session
    }

    func fetchPulls(filter: String) async throws -> [Edge] {
        guard !token.isEmpty else { return [] }

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

        while true {
            let response: GraphQLSearchResponse = try await postGraphQL(
                query: graphQLQuery,
                variables: GraphQLVariables(searchQuery: queryString, cursor: cursor)
            )
            edges.append(contentsOf: response.data.search.edges)

            guard response.data.search.pageInfo.hasNextPage else { break }
            guard let nextCursor = response.data.search.pageInfo.endCursor,
                  nextCursor != cursor else {
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

    func fetchUser() async throws -> User {
        try await performRequest(
            url: endpoint("user"),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    private func performRequest<T: Decodable>(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = cachePolicy

        let (data, response) = try await session.data(for: request)
        try Self.validateResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postGraphQL<T: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables
    ) async throws -> T {
        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        let (data, response) = try await session.data(for: request)
        try Self.validateResponse(response)

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

    private static func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(statusCode)"
            ])
        }
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
        query PullRequests($query: String!, $cursor: String) {
            search(query: $query, type: ISSUE, first: 100, after: $cursor) {
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
        messages.joined(separator: "\n")
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

    enum CodingKeys: String, CodingKey {
        case searchQuery = "query"
        case cursor
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
