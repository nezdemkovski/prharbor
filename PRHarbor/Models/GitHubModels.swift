
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
    var stack: PullRequestStack? = nil
    var stackEntry: PullRequestStackPosition? = nil
    var baseRefName: String? = nil
    var timelineItems: PullTimelineConnection? = nil
    var reviewRequests: PullReviewRequests? = nil
}

nonisolated struct PullRequestStack: Codable, Sendable, Equatable {
    var id: String
    var number: Int
    var baseRefName: String
    var size: Int
    var entries: PullRequestStackEntries? = nil
}

nonisolated struct PullRequestStackEntries: Codable, Sendable, Equatable {
    var nodes: [PullRequestStackEntry]
}

nonisolated struct PullRequestStackEntry: Codable, Sendable, Equatable, Identifiable {
    var position: Int
    var pullRequest: StackedPullRequest?

    var id: String { pullRequest?.url.absoluteString ?? "stack-position-\(position)" }
}

nonisolated struct PullRequestStackPosition: Codable, Sendable, Equatable {
    var position: Int
}

nonisolated struct StackedPullRequest: Codable, Sendable, Equatable {
    var id: String
    var number: Int
    var title: String
    var url: URL
    var state: String
    var isDraft: Bool
    var headRefName: String
    var headRefOid: String
    var reviewDecision: String?
    var mergeable: String?
}

nonisolated struct StackRebaseResult: Sendable, Equatable {
    let rebasedCount: Int
    let totalCount: Int
}

nonisolated enum StackRebaseError: LocalizedError, Sendable, Equatable {
    case noOpenPullRequests
    case conflictingBranch(String)
    case incompleteStack(expected: Int, available: Int)
    case partial(completed: Int, total: Int, failedBranch: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noOpenPullRequests:
            "This stack has no open pull requests to rebase."
        case .conflictingBranch(let branch):
            "Can't rebase: \(branch) has merge conflicts."
        case .incompleteStack(let expected, let available):
            "Can't rebase: loaded \(available) of \(expected) stack layers. Refresh and try again."
        case .partial(let completed, let total, let failedBranch, let reason):
            "Rebased \(completed) of \(total). \(failedBranch) failed: \(reason)"
        }
    }
}

nonisolated struct PullDisplayGroup: Identifiable, Sendable, Equatable {
    var id: String
    var stack: PullRequestStack?
    var edges: [Edge]
}

nonisolated func groupPullsForDisplay(_ edges: [Edge]) -> [PullDisplayGroup] {
    let stackEdges = Dictionary(grouping: edges.compactMap { edge -> (String, Edge)? in
        guard let stack = edge.node.stack, stack.size > 1 else { return nil }
        return (stack.id, edge)
    }, by: { $0.0 })
    .mapValues { pairs in pairs.map(\.1) }

    var seenStackIDs = Set<String>()
    return edges.compactMap { edge in
        guard let stack = edge.node.stack, stack.size > 1 else {
            return PullDisplayGroup(
                id: edge.node.url.absoluteString,
                stack: nil,
                edges: [edge]
            )
        }

        guard seenStackIDs.insert(stack.id).inserted else { return nil }
        let orderedEdges = (stackEdges[stack.id] ?? [edge]).sorted { first, second in
            let firstPosition = first.node.stackEntry?.position ?? .max
            let secondPosition = second.node.stackEntry?.position ?? .max
            if firstPosition == secondPosition {
                return first.node.number > second.node.number
            }
            return firstPosition > secondPosition
        }
        let detailedStack = orderedEdges.compactMap(\.node.stack).first { $0.entries != nil } ?? stack
        return PullDisplayGroup(id: stack.id, stack: detailedStack, edges: orderedEdges)
    }
}

nonisolated struct GraphQLStackResponse: Codable, Sendable {
    var data: StackResponseData
}

nonisolated struct StackResponseData: Codable, Sendable {
    var nodes: [PullRequestStack?]
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
    // Actions mode fetches aggregate state without the commit-status detail list.
    var contexts: ContextNodes? = nil
}

nonisolated struct ContextNodes: Codable, Hashable, Sendable {
    var nodes: [ContextNode]
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

// GitHub's timeline is decoded as a small union; absent fields stay compatible with older payloads.
nonisolated struct PullTimelineConnection: Codable, Sendable, Equatable {
    var nodes: [PullTimelineNode?]
    var pageInfo: PullTimelinePageInfo?
}
nonisolated struct PullTimelinePageInfo: Codable, Sendable, Equatable {
    var hasPreviousPage: Bool
}
nonisolated struct PullTimelineNode: Codable, Sendable, Equatable {
    var __typename: String
    var createdAt: Date?
    var submittedAt: Date?
    var state: String?
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
nonisolated struct PullReviewRequest: Codable, Sendable, Equatable {
    var requestedReviewer: TimelineReviewer?
}
