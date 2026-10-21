import Foundation

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
    var author: User?
    var repository: Repository
    var commits: CommitsNodes?
    var headRefName: String
    var isDraft: Bool
    var reviewDecision: ReviewDecision?
    var mergeable: MergeableState?
    var stack: PullRequestStack? = nil
    var stackEntry: PullRequestStackPosition? = nil
    var baseRefName: String? = nil
    var timelineItems: PullTimelineConnection? = nil
    var reviewRequests: PullReviewRequests? = nil
}

nonisolated struct User: Codable, Sendable, Equatable {
    var login: String
    var avatarUrl: URL?

}

nonisolated struct Repository: Codable, Sendable, Equatable {
    var name: String
    var nameWithOwner: String
}
