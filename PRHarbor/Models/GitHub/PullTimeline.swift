import Foundation

// GitHub's timeline is decoded as a small union; absent fields stay compatible with older payloads.
nonisolated struct PullTimelineConnection: Codable, Sendable, Equatable {
    var nodes: [PullTimelineNode?]
    var pageInfo: PullTimelinePageInfo?
}

nonisolated extension PullTimelineConnection {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeIfPresent([PullTimelineNode?].self, forKey: .nodes) ?? []
        pageInfo = try container.decodeIfPresent(PullTimelinePageInfo.self, forKey: .pageInfo)
    }
}

nonisolated struct PullTimelinePageInfo: Codable, Sendable, Equatable {
    var hasPreviousPage: Bool
}

nonisolated struct PullTimelineNode: Codable, Sendable, Equatable {
    var __typename: String
    var createdAt: Date?
    var submittedAt: Date?
    var state: ReviewState?
    var author: User?
    var commit: TimelineCommit?
    var requestedReviewer: TimelineReviewer?
}

nonisolated struct TimelineCommit: Codable, Sendable, Equatable {
    var committedDate: Date
}

nonisolated struct TimelineReviewer: Codable, Sendable, Equatable {
    var login: String?
    var avatarUrl: URL?
    var name: String?
    var __typename: String? = nil
}

nonisolated struct PullReviewRequests: Codable, Sendable, Equatable {
    var nodes: [PullReviewRequest]
}

nonisolated extension PullReviewRequests {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([PullReviewRequest].self, forKey: .nodes)
    }
}

nonisolated struct PullReviewRequest: Codable, Sendable, Equatable {
    var requestedReviewer: TimelineReviewer?
}
