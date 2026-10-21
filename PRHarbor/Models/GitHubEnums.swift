import Foundation

/// A GitHub GraphQL enum. A value the schema adds later decodes as `unknown` instead of
/// failing the whole page.
nonisolated protocol GitHubEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

nonisolated extension GitHubEnum {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

/// `MergeableState`: whether a pull request merges cleanly into its base.
nonisolated enum MergeableState: String, GitHubEnum {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// `PullRequestReviewDecision`: the review status that branch protection sees.
nonisolated enum ReviewDecision: String, GitHubEnum {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case unknown = "UNKNOWN"
}

/// `PullRequestState`.
nonisolated enum PullRequestState: String, GitHubEnum {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
    case unknown = "UNKNOWN"
}

/// `PullRequestReviewState`: the outcome of one submitted review.
nonisolated enum ReviewState: String, GitHubEnum {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case dismissed = "DISMISSED"
    case pending = "PENDING"
    case unknown = "UNKNOWN"
}
