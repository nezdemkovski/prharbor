
import Foundation

nonisolated struct GraphQLSearchResponse: Codable, Sendable {
    var data: ResponseData
}

nonisolated struct ResponseData: Codable, Sendable {
    var search: Search
}

nonisolated struct Search: Codable, Sendable {
    var edges: [Edge]
    var issueCount: Int
    var pageInfo: PageInfo
}

nonisolated struct PageInfo: Codable, Sendable {
    var hasNextPage: Bool
    var endCursor: String?
}

nonisolated struct Edge: Codable, Sendable, Equatable {
    var node: Pull
}

nonisolated struct Pull: Codable, Sendable, Equatable {
    var url: URL
    var updatedAt: Date
    var createdAt: Date
    var title: String
    var number: Int
    var deletions: Int?
    var additions: Int?
    var reviews: Review
    var author: User?
    var repository: Repository
    var commits: CommitsNodes?
    var labels: Nodes<Label>
    var headRefName: String
    var isDraft: Bool
    var isReadByViewer: Bool
    var reviewDecision: String?
    var mergeable: String?
}

nonisolated struct Nodes<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var nodes: [T]
}

nonisolated struct Review: Codable, Sendable, Equatable {
    var totalCount: Int
    var edges: [UserEdge]
}

nonisolated struct UserEdge: Codable, Sendable, Equatable {
    var node: UserNode
}

nonisolated struct UserNode: Codable, Sendable, Equatable {
    var author: User?
}

nonisolated struct User: Codable, Sendable, Equatable {
    var login: String
    var avatarUrl: URL?

}

nonisolated struct Repository: Codable, Sendable, Equatable {
    var name: String
    var nameWithOwner: String
}

nonisolated struct CommitsNodes: Codable, Sendable, Equatable {
    var nodes: [Commit]
}

nonisolated struct Commit: Codable, Hashable, Sendable {
    var commit: CheckSuites
}

nonisolated struct CheckSuites: Codable, Hashable, Sendable {
    var checkSuites: CheckSuitsNodes?
    var statusCheckRollup: StatusCheckRollup?
}

nonisolated struct CheckSuitsNodes: Codable, Hashable, Sendable {
    var nodes: [CheckSuit]
}

nonisolated struct CheckSuiteApp: Codable, Hashable, Sendable {
    var name: String?
}

nonisolated struct CheckSuit: Codable, Hashable, Sendable {
    var app: CheckSuiteApp?
    var checkRuns: CheckRun
}

nonisolated struct CheckRun: Codable, Hashable, Sendable {
    var totalCount: Int
    var nodes: [Check]
}

nonisolated struct Check: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var conclusion: String?
    var detailsUrl: URL

    var id: String { "\(name)-\(detailsUrl.absoluteString)" }
}

nonisolated struct Label: Codable, Hashable, Sendable {
    var name: String
    var color: String
}

nonisolated struct StatusCheckRollup: Codable, Hashable, Sendable {
    var state: String
    var contexts: ContextNodes
}

nonisolated struct ContextNodes: Codable, Hashable, Sendable {
    var nodes: [ContextNode]
}
nonisolated struct DeviceCodeResponse: Codable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

nonisolated struct DeviceTokenResponse: Codable, Sendable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}
nonisolated struct ContextNode: Codable, Hashable, Sendable, Identifiable {
    var name: String?
    var context: String?
    var conclusion: String?
    var state: String?
    var title: String?
    var description: String?
    var detailsUrl: URL?
    var targetUrl: String?

    var id: String { name ?? context ?? title ?? "\(state ?? "unknown")-\(targetUrl ?? "")-\(description ?? "")" }
}
