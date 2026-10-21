import Foundation

// Parse GitHub history once per input change, rather than for every row and toolbar control.
nonisolated struct TimelineInput: Equatable, Sendable {
    var edges: [Edge]
    var reviewURLs: Set<URL>
    var username: String
    var now: Date
    var thresholds: [Int]
    var bots: [String]
    var ownComments: Bool
    var snoozed: [String: Double]
    var sources: [URL: PullSources] = [:]

    init(edges: [Edge], reviewURLs: Set<URL>, username: String, now: Date,
         thresholds: [Int], bots: [String], ownComments: Bool, snoozed: [String: Double]) {
        self.edges = edges
        self.reviewURLs = reviewURLs
        self.username = username
        self.now = now
        self.thresholds = thresholds
        self.bots = bots
        self.ownComments = ownComments
        self.snoozed = snoozed
    }

    init(assigned: [Edge], created: [Edge], requested: [Edge],
         includeAssigned: Bool = true, includeCreated: Bool = true, includeRequested: Bool = true,
         username: String, now: Date, thresholds: [Int], bots: [String],
         ownComments: Bool, snoozed: [String: Double]) {
        self.init(edges: (includeRequested ? requested : []) + (includeAssigned ? assigned : []) + (includeCreated ? created : []),
                  reviewURLs: Set(requested.map { $0.node.url }), username: username, now: now,
                  thresholds: thresholds, bots: bots, ownComments: ownComments, snoozed: snoozed)
        for (source, edges) in [(PullSources.assigned, assigned), (.created, created), (.requested, requested)] {
            for edge in edges { sources[edge.node.url, default: []].insert(source) }
        }
    }
    func makeItems() -> [TimelineItem] {
        var seen = Set<String>()
        let matcher = TimelineBotMatcher(patterns: bots)
        return edges.filter { seen.insert($0.node.url.absoluteString).inserted }.map { edge in
            TimelineItem(pull: edge.node, username: username, now: now, thresholds: thresholds,
                         bots: bots, ownComments: ownComments,
                         snoozedUntil: snoozed[edge.node.url.absoluteString].map { Date(timeIntervalSince1970: $0) },
                         reviewRequested: reviewURLs.contains(edge.node.url),
                         sources: sources[edge.node.url] ?? .all, botMatcher: matcher)
        }
    }
}
