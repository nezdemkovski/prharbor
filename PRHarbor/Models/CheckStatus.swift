import Foundation

nonisolated struct CICheck: Identifiable, Equatable, Sendable {
    let name: String
    let status: String
    let url: URL?
    let index: Int

    var id: String { "\(name)-\(index)" }

    static func from(commits: CommitsNodes) -> [CICheck] {
        var result: [CICheck] = []
        if let suites = commits.nodes.first?.commit.checkSuites {
            for suite in suites.nodes {
                for check in suite.checkRuns.nodes {
                    result.append(CICheck(name: check.name, status: check.conclusion ?? "PENDING", url: check.detailsUrl, index: result.count))
                }
            }
        } else if let rollup = commits.nodes.first?.commit.statusCheckRollup {
            for node in rollup.contexts?.nodes ?? [] {
                let name = node.name ?? node.context ?? "Check"
                let status = node.conclusion ?? node.state ?? "PENDING"
                let url = node.detailsUrl ?? (node.targetUrl.flatMap { URL(string: $0) })
                result.append(CICheck(name: name, status: status, url: url, index: result.count))
            }
        }
        return result
    }
}

// Details are a bounded slice. Only the server's overall state can establish
// success; an old cache without a rollup must remain unknown.
nonisolated func ciAggregateStatus(_ commits: CommitsNodes?) -> CIStatusKind? {
    if let state = commits?.nodes.first?.commit.statusCheckRollup?.state { return ciStatusKind(state) }
    // A legacy cache can establish observed trouble, but cannot prove success.
    let observed = commits.map(CICheck.from)?.map { ciStatusKind($0.status) } ?? []
    if observed.contains(.failure) { return .failure }
    if observed.contains(.pending) { return .pending }
    return nil
}


nonisolated enum CIStatusKind: Equatable, Sendable {
    case success
    case failure
    case pending
    case neutral
}

nonisolated func ciStatusKind(_ status: String) -> CIStatusKind {
    switch status.uppercased() {
    case "SUCCESS":
        .success
    case "ERROR", "FAILURE", "CANCELLED", "STALE", "STARTUP_FAILURE", "TIMED_OUT":
        .failure
    case "EXPECTED", "PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "ACTION_REQUIRED":
        .pending
    default:
        .neutral
    }
}
