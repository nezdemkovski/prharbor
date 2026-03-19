import SwiftUI
import Defaults

struct PRListView: View {
    let edges: [Edge]
    let tabName: String
    let config: PRDisplayConfig
    @Binding var expandedPRUrl: String?
    @Binding var searchText: String
    var onAddToFeature: ((String) -> Void)?

    @Default(.sortOrder) private var sortOrder
    @Default(.groupByRepo) private var groupByRepo
    @Default(.collapsedRepos) private var collapsedReposArray

    private var collapsedRepos: Set<String> {
        get { Set(collapsedReposArray) }
    }

    private func toggleRepo(_ repo: String) {
        if collapsedReposArray.contains(repo) {
            collapsedReposArray.removeAll { $0 == repo }
        } else {
            collapsedReposArray.append(repo)
        }
    }

    private var filtered: [Edge] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let base = query.isEmpty ? edges : edges.filter { edge in
            let p = edge.node
            return p.title.lowercased().contains(query)
                || p.repository.name.lowercased().contains(query)
                || (p.author?.login.lowercased().contains(query) ?? false)
                || "#\(p.number)".contains(query)
                || p.headRefName.lowercased().contains(query)
        }
        return base.sorted { a, b in
            switch sortOrder {
            case .updatedNewest: return a.node.updatedAt > b.node.updatedAt
            case .updatedOldest: return a.node.updatedAt < b.node.updatedAt
            case .createdNewest: return a.node.createdAt > b.node.createdAt
            case .createdOldest: return a.node.createdAt < b.node.createdAt
            }
        }
    }

    private var groupedByRepo: [(String, [Edge])] {
        let dict = Dictionary(grouping: filtered) { $0.node.repository.name }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        if edges.isEmpty {
            EmptyStateView(icon: "tray", title: "All clear", subtitle: "No \(tabName.lowercased()) PRs")
        } else if filtered.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "No matches")
        } else {
            PRScrollContainer {
                if groupByRepo {
                    ForEach(groupedByRepo, id: \.0) { repo, repoEdges in
                        CollapsibleHeader(
                            repo,
                            count: repoEdges.count,
                            isCollapsed: collapsedRepos.contains(repo),
                            onToggle: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    toggleRepo(repo)
                                }
                            }
                        )
                        if !collapsedRepos.contains(repo) {
                            PRRowsContainer(
                                edges: repoEdges,
                                config: config,
                                expandedPRUrl: $expandedPRUrl,
                                onAddToFeature: onAddToFeature
                            )
                        }
                    }
                } else {
                    PRRowsContainer(
                        edges: filtered,
                        config: config,
                        expandedPRUrl: $expandedPRUrl,
                        onAddToFeature: onAddToFeature
                    )
                }
            }
        }
    }
}
