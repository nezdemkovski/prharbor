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
        let graphQLQuery = buildGraphQLQuery()
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

        return edges
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

    private func postGraphQL<T: Decodable>(query: String, variables: GraphQLVariables) async throws -> T {
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

    private func buildGraphQLQuery() -> String {
        let buildFields: String

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
}

private nonisolated struct GraphQLRequest: Encodable {
    let query: String
    let variables: GraphQLVariables
}

nonisolated struct GraphQLVariables: Encodable, Sendable {
    let searchQuery: String
    let cursor: String?

    enum CodingKeys: String, CodingKey {
        case searchQuery = "query"
        case cursor
    }
}
