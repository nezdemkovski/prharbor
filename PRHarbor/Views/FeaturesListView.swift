import SwiftUI
import Defaults

struct FeaturesListView: View {
    @Binding var features: [PRFeature]
    let allPulls: [Edge]
    let config: PRDisplayConfig
    @Binding var expandedPRUrl: String?
    var onRename: ((UUID) -> Void)?
    var onPromote: ((String, [Edge]) -> Void)?
    var onConfirm: ((String, String, Bool, @escaping () -> Void) -> Void)?
    @Default(.hiddenAutoBranches) private var hiddenAutoBranches
    @State private var collapsedFeatures: Set<UUID> = []

    private func pullsFor(feature: PRFeature) -> [Edge] {
        allPulls.filter { feature.prURLs.contains($0.node.url.absoluteString) }
    }

    private var autoFeatures: [(branch: String, edges: [Edge])] {
        let manualPRUrls = Set(features.flatMap { $0.prURLs })
        let grouped = Dictionary(grouping: allPulls) { $0.node.headRefName }
        return grouped
            .filter { $0.value.count >= 2 }
            .filter { !hiddenAutoBranches.contains($0.key) }
            .filter { group in !group.value.allSatisfy { manualPRUrls.contains($0.node.url.absoluteString) } }
            .map { (branch: $0.key, edges: $0.value) }
            .sorted { $0.branch < $1.branch }
    }

    private var hasContent: Bool {
        !features.isEmpty || !autoFeatures.isEmpty
    }

    private func copyPullLinks(_ edges: [Edge]) {
        let text = edges
            .map { "\($0.node.title): \($0.node.url.absoluteString)" }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        if !hasContent {
            EmptyStateView(
                icon: "puzzlepiece.extension",
                title: "No features yet",
                subtitle: "Pin PRs or use matching branch names\nacross repos to auto-group"
            )
        } else {
            PRScrollContainer {
                ForEach(features) { feature in
                    let isCollapsed = collapsedFeatures.contains(feature.id)
                    let featurePulls = pullsFor(feature: feature)

                    CollapsibleHeader(
                        feature.name,
                        count: featurePulls.count,
                        isCollapsed: isCollapsed,
                        onToggle: {
                            withAnimation(.snappy(duration: 0.2)) {
                                if isCollapsed {
                                    collapsedFeatures.remove(feature.id)
                                } else {
                                    collapsedFeatures.insert(feature.id)
                                }
                            }
                        }
                    ) {
                        if !featurePulls.isEmpty {
                            CircleIconButton(icon: "doc.on.doc", help: "Copy PR links") {
                                copyPullLinks(featurePulls)
                            }
                        }
                        CircleIconButton(icon: "pencil", help: "Rename") {
                            onRename?(feature.id)
                        }
                        CircleIconButton(icon: "trash", color: Theme.failure, background: Theme.failure.opacity(0.1), help: "Delete") {
                            let id = feature.id
                            let name = feature.name
                            onConfirm?("Delete \"\(name)\"?", "Delete", true, {
                                features.removeAll { $0.id == id }
                            })
                        }
                    }

                    if !isCollapsed {
                        if featurePulls.isEmpty {
                            Text("No matching PRs")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Theme.rowPaddingH)
                                .padding(.vertical, 4)
                        } else {
                            PRRowsContainer(
                                edges: featurePulls,
                                config: config,
                                expandedPRUrl: $expandedPRUrl,
                                idPrefix: feature.id.uuidString
                            )
                        }
                    }
                }

                if !autoFeatures.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9))
                        SectionTitle("Auto-detected")
                        VStack { Divider().opacity(0.3) }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.rowPaddingH)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                    ForEach(autoFeatures, id: \.branch) { branch, branchEdges in
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.success)
                            Text(branch)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(branchEdges.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            VStack { Divider().opacity(0.3) }

                            CircleIconButton(icon: "doc.on.doc", size: 9, frameSize: 18, help: "Copy PR links") {
                                copyPullLinks(branchEdges)
                            }
                            CircleIconButton(icon: "puzzlepiece.extension", size: 9, frameSize: 18, help: "Save as feature") {
                                onPromote?(branch, branchEdges)
                            }
                            CircleIconButton(icon: "eye.slash", size: 9, frameSize: 18, color: Color.secondary, help: "Hide") {
                                let b = branch
                                let shortName = b.components(separatedBy: "/").last ?? b
                                onConfirm?("Hide \"\(shortName)\"?", "Hide", true, {
                                    Defaults[.hiddenAutoBranches].append(b)
                                })
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.rowPaddingH)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                        PRRowsContainer(
                            edges: branchEdges,
                            config: config,
                            expandedPRUrl: $expandedPRUrl,
                            idPrefix: "auto-\(branch)"
                        )
                    }
                }
            }
        }
    }
}
