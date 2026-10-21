import Foundation

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

nonisolated extension PullRequestStackEntries {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([PullRequestStackEntry].self, forKey: .nodes)
    }
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
    var state: PullRequestState
    var isDraft: Bool
    var headRefName: String
    var headRefOid: String
    var reviewDecision: ReviewDecision?
    var mergeable: MergeableState?
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
    let stackEdges = Dictionary(
        grouping: edges.compactMap { edge -> (String, Edge)? in
            guard let stack = edge.node.stack, stack.size > 1 else { return nil }
            return (stack.id, edge)
        }, by: { $0.0 }
    )
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
