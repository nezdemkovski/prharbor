
import Foundation
import Defaults
import KeychainAccess

@MainActor
struct GitHubClient {

    @FromKeychain(.githubToken) var githubToken
    func fetchPulls(filter: String) async throws -> [Edge] {
        guard Defaults[.githubUsername] != "", githubToken != "" else {
            return []
        }

        let queryString = "is:open is:pr \(filter) archived:false"
        let graphQlQuery = buildGraphQlQuery(queryString: queryString)
        let token = githubToken
        let baseUrl = Defaults[.githubApiBaseUrl]

        let response: GraphQlSearchResp = try await Self.postGraphQL(query: graphQlQuery, token: token, baseUrl: baseUrl)
        return response.data.search.edges
    }

    func fetchUser() async throws -> User {
        let token = githubToken
        let baseUrl = Defaults[.githubApiBaseUrl]

        guard let url = URL(string: baseUrl + "/user") else {
            throw URLError(.badURL)
        }

        return try await Self.performRequest(
            url: url,
            token: token,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }
    private static func performRequest<T: Decodable>(
        url: URL,
        token: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = cachePolicy

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private static func postGraphQL<T: Decodable>(query: String, token: String, baseUrl: String) async throws -> T {
        guard let url = URL(string: baseUrl + "/graphql") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = ["query": query, "variables": [String: String]()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        do {
            return try GithubDecoder().decode(T.self, from: data)
        } catch {
            print("GraphQL decode error: \(error)")
            if let json = String(data: data, encoding: .utf8) {
                print("GraphQL response: \(json.prefix(500))")
            }
            throw error
        }
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

    private func buildGraphQlQuery(queryString: String) -> String {
        let escapedQuery = queryString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var build = ""

        switch Defaults[.buildType] {
        case .checks:
            build = """
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
            build = """
        commits(last: 1) {
            nodes {
                commit {
                    statusCheckRollup {
                        state
                        contexts (first: 20) {
                            nodes {
                                ... on StatusContext {
                                    context
                                    description
                                    state
                                    targetUrl
                                    description
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
        default:
            build = ""
        }

        return """
        {
            search(query: "\(escapedQuery)", type: ISSUE, first: 30) {
                issueCount
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
                            \(build)
                        }
                    }
                }
            }
        }
        """
    }
}

final class GithubDecoder: JSONDecoder, @unchecked Sendable {
    override init() {
        super.init()
        dateDecodingStrategy = .iso8601
    }
}
