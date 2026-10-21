import Foundation

nonisolated struct CommitsNodes: Codable, Sendable, Equatable {
    var nodes: [Commit]
}

nonisolated extension CommitsNodes {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([Commit].self, forKey: .nodes)
    }
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

nonisolated extension CheckSuitsNodes {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([CheckSuit].self, forKey: .nodes)
    }
}

nonisolated struct CheckSuiteApp: Codable, Hashable, Sendable {
    var name: String?
}

nonisolated struct CheckSuit: Codable, Hashable, Sendable {
    var app: CheckSuiteApp?
    var checkRuns: CheckRun?
}

nonisolated struct CheckRun: Codable, Hashable, Sendable {
    var nodes: [Check]
}

nonisolated extension CheckRun {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([Check].self, forKey: .nodes)
    }
}

nonisolated struct Check: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var conclusion: String?
    var detailsUrl: URL?

    var id: String { "\(name)-\(detailsUrl?.absoluteString ?? "")" }
}

nonisolated struct StatusCheckRollup: Codable, Hashable, Sendable {
    var state: String
    // Actions mode fetches aggregate state without the commit-status detail list.
    var contexts: ContextNodes? = nil
}

nonisolated struct ContextNodes: Codable, Hashable, Sendable {
    var nodes: [ContextNode]
}

nonisolated extension ContextNodes {
    init(from decoder: Decoder) throws {
        nodes = try decoder.container(keyedBy: CodingKeys.self).decodeCompact([ContextNode].self, forKey: .nodes)
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
