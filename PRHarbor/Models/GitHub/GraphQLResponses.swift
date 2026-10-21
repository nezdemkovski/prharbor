import Foundation

/// Phase one of a refresh: a search page of identities and change markers.
nonisolated struct GraphQLSummaryResponse: Decodable, Sendable {
    var data: SummaryData

    struct SummaryData: Decodable, Sendable {
        var search: SummaryPage
        /// The account that answered the query, compared with the connected account.
        var viewer: User?
    }
}

nonisolated struct SummaryPage: Decodable, Sendable {
    var nodes: [PullSummary]
    var pageInfo: PageInfo
    fileprivate enum CodingKeys: String, CodingKey { case nodes, pageInfo }
}

nonisolated extension SummaryPage {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeCompact([PullSummary].self, forKey: .nodes)
        pageInfo = try container.decode(PageInfo.self, forKey: .pageInfo)
    }
}

/// Enough of a pull request to tell whether cached details are still current.
nonisolated struct PullSummary: Decodable, Sendable {
    var id: String
    var url: URL
    var updatedAt: Date
    var isDraft: Bool
    var mergeable: MergeableState?
    var stack: PullRequestStack?
    var stackEntry: PullRequestStackPosition?
    var commits: CommitsNodes?

    var ciState: String? { commits?.nodes.first?.commit.statusCheckRollup?.state }
}

/// Phase two: full details for the requested node IDs.
nonisolated struct GraphQLDetailsResponse: Decodable, Sendable {
    var data: DetailsData

    struct DetailsData: Decodable, Sendable {
        var nodes: [Pull]
        fileprivate enum CodingKeys: String, CodingKey { case nodes }
    }
}

nonisolated extension GraphQLDetailsResponse.DetailsData {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([Pull].self, forKey: .nodes)
    }
}

nonisolated struct GraphQLStackResponse: Codable, Sendable {
    var data: StackResponseData
}

nonisolated struct StackResponseData: Codable, Sendable {
    var nodes: [PullRequestStack?]
}

// GraphQL lists and their elements are nullable throughout GitHub's schema, for example
// when an item is hidden from the token. A null list or element is skipped rather than
// failing the whole page; the request's own errors are reported separately.
nonisolated extension KeyedDecodingContainer {
    func decodeCompact<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T?].self, forKey: key)?.compactMap { $0 } ?? []
    }
}
