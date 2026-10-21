import Foundation

/// The three GitHub searches a refresh runs for the connected account.
nonisolated enum PullSearch: CaseIterable, Sendable {
    case assigned, created, requested

    func filter(username: String) -> String {
        switch self {
        case .assigned: "assignee:\(username)"
        case .created: "author:\(username)"
        case .requested: "review-requested:\(username)"
        }
    }

    func isEnabled(in scope: PullSnapshotScope) -> Bool {
        switch self {
        case .assigned: scope.assigned
        case .created: scope.created
        case .requested: scope.requested
        }
    }

    var source: PullSources {
        switch self {
        case .assigned: .assigned
        case .created: .created
        case .requested: .requested
        }
    }

    struct Result: Sendable {
        let search: PullSearch
        let edges: Swift.Result<[Edge], Error>
    }

    /// Runs every search concurrently and yields each as it finishes. A disabled search yields
    /// no pull requests; drafts are dropped here when the scope hides them.
    static func run(client: GitHubClient, scope: PullSnapshotScope, known: [URL: Pull]) -> AsyncStream<Result> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Result.self) { group in
                    for search in allCases {
                        group.addTask {
                            do {
                                var edges = search.isEnabled(in: scope)
                                    ? try await client.fetchPulls(filter: search.filter(username: scope.username), known: known) : []
                                if scope.hideDrafts { edges = edges.filter { !$0.node.isDraft } }
                                return Result(search: search, edges: .success(edges))
                            } catch {
                                return Result(search: search, edges: .failure(error))
                            }
                        }
                    }
                    for await result in group { continuation.yield(result) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
