import Foundation

nonisolated struct PullRefreshTracker: Sendable {
    private var knownURLs: Set<String> = []
    private var wasFetched = false

    mutating func update(edges: [Edge], fetched: Bool, canNotify: Bool) -> [Pull] {
        let newPulls: [Pull]
        if canNotify && fetched && wasFetched {
            newPulls = edges
                .filter { !knownURLs.contains($0.node.url.absoluteString) }
                .map(\.node)
        } else {
            newPulls = []
        }

        if fetched {
            knownURLs = Set(edges.map { $0.node.url.absoluteString })
        }
        wasFetched = fetched
        return newPulls
    }

    mutating func reset() {
        knownURLs = []
        wasFetched = false
    }
}
