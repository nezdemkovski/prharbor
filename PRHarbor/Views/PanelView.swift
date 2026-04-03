
import SwiftUI
import Defaults

enum PRTab: String, CaseIterable {
    case reviewRequested = "Review Requested"
    case assigned = "Assigned"
    case created = "My PRs"
    case features = "Features"
}

enum PanelPage {
    case main
    case settings
    case about
}

struct ConfirmState {
    let message: String
    let action: String
    let isDestructive: Bool
    let handler: () -> Void
}

struct PanelView: View {
    @ObservedObject var store: PullRequestStore
    var onQuit: () -> Void

    @Default(.clickOpensLink) private var clickOpensLink
    @Default(.showAvatar) private var showAvatar
    @Default(.showLabels) private var showLabels
    @Default(.showUnreadDot) private var showUnreadDot
    @Default(.showLinesChanged) private var showLinesChanged
    @Default(.showApprovals) private var showApprovals
    @Default(.githubUsername) private var githubUsername
    @Default(.staleDays) private var staleDays
    @Default(.features) private var features
    @State private var selectedTab: PRTab = .reviewRequested
    @State private var expandedPRUrl: String?
    @State private var page: PanelPage = .main
    @State private var showQuitConfirmation = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var addingToFeaturePR: String?
    @State private var isCreatingFeature = false
    @State private var newFeatureName = ""
    @State private var renamingFeatureId: UUID?
    @State private var renameText = ""
    @State private var promotingBranch: String?
    @State private var promoteEdges: [Edge] = []
    @State private var promoteName = ""
    @State private var confirmState: ConfirmState?

    private var displayConfig: PRDisplayConfig {
        PRDisplayConfig(
            showAvatar: showAvatar,
            showLabels: showLabels,
            showUnreadDot: showUnreadDot,
            showLinesChanged: showLinesChanged,
            showApprovals: showApprovals,
            clickOpensLink: clickOpensLink,
            githubUsername: githubUsername,
            staleDays: staleDays
        )
    }

    private var allPulls: [Edge] {
        var seen = Set<String>()
        var result: [Edge] = []
        for edge in store.reviewRequestedPulls + store.assignedPulls + store.createdPulls {
            let url = edge.node.url.absoluteString
            if seen.insert(url).inserted {
                result.append(edge)
            }
        }
        return result
    }

    private func pulls(for tab: PRTab) -> [Edge] {
        switch tab {
        case .reviewRequested: store.reviewRequestedPulls
        case .assigned: store.assignedPulls
        case .created: store.createdPulls
        case .features: [] // handled separately
        }
    }

    private func count(for tab: PRTab) -> Int {
        if tab == .features { return features.count }
        return pulls(for: tab).count
    }

    private func isTabEnabled(_ tab: PRTab) -> Bool {
        switch tab {
        case .reviewRequested: Defaults[.showRequested]
        case .assigned: Defaults[.showAssigned]
        case .created: Defaults[.showCreated]
        case .features: Defaults[.showFeatures]
        }
    }

    private var enabledTabs: [PRTab] {
        PRTab.allCases.filter { isTabEnabled($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ZStack {
                prContent
                    .opacity(page == .main ? 1 : 0)
                    .allowsHitTesting(page == .main)

                PanelSettingsView(store: store)
                    .opacity(page == .settings ? 1 : 0)
                    .allowsHitTesting(page == .settings)

                AboutView()
                    .opacity(page == .about ? 1 : 0)
                    .allowsHitTesting(page == .about)
            }
            .animation(.easeInOut(duration: 0.15), value: page)
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(Theme.panelMaterial)
    }
    private var headerView: some View {
        VStack(spacing: 0) {
            if page != .main {
                HStack(spacing: 10) {
                    HeaderIconButton(icon: "chevron.left", help: "Back") {
                        withAnimation(.snappy(duration: 0.2)) { page = .main }
                    }

                    Text(page == .settings ? "Settings" : "About")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)

                    Color.clear.frame(width: 24, height: 1)
                }
                .padding(.horizontal, Theme.headerPaddingH)
                .padding(.vertical, Theme.headerPaddingV)
            } else {
                HStack(spacing: 6) {
                    Image("git-pull-request")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .opacity(0.7)
                    Text("PR Harbor")
                        .font(.system(.subheadline, weight: .bold))

                    if store.isConfigured {
                        statusPill
                    }

                    Spacer()

                    if store.isConfigured {
                        headerButton(icon: "arrow.clockwise", help: "Refresh") {
                            store.refresh()
                        }
                        headerButton(icon: "magnifyingglass", help: "Search") {
                            withAnimation(.snappy(duration: 0.2)) {
                                isSearching.toggle()
                                if !isSearching { searchText = "" }
                            }
                        }
                    }

                    headerButton(icon: "gearshape", help: "Settings") {
                        withAnimation(.snappy(duration: 0.2)) { page = .settings }
                    }

                    headerButton(icon: "info.circle", help: "About") {
                        withAnimation(.snappy(duration: 0.2)) { page = .about }
                    }

                    if showQuitConfirmation {
                        HStack(spacing: 4) {
                            Button("Quit") { onQuit() }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.failure)
                                .buttonStyle(.plain)
                            Text("/")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                            Button("Cancel") {
                                withAnimation(.snappy(duration: 0.15)) {
                                    showQuitConfirmation = false
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    } else {
                        headerButton(icon: "power", help: "Quit") {
                            withAnimation(.snappy(duration: 0.15)) {
                                showQuitConfirmation = true
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.headerPaddingH)
                .padding(.top, Theme.headerPaddingV)
                .padding(.bottom, 6)

                if store.isConfigured && !store.isEmpty {
                    Group {
                        if isSearching {
                            headerSearchField
                        } else {
                            headerTabs
                        }
                    }
                    .frame(height: 28)
                    .padding(.bottom, 4)
                }
            }

            Divider().opacity(0.5)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if store.isLoading {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.cardBackground, in: Capsule())
        } else if store.minutesUntilRefresh > 0 {
            Text("\(store.minutesUntilRefresh)m")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var headerTabs: some View {
        HStack(spacing: 4) {
            ForEach(enabledTabs, id: \.self) { tab in
                TabPill(
                    title: tab.rawValue,
                    count: count(for: tab),
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedTab = tab
                        expandedPRUrl = nil
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.headerPaddingH)
    }

    private var headerSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField("Search PRs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    searchText = ""
                    isSearching = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.cardBackground, in: Capsule())
        .padding(.horizontal, Theme.headerPaddingH)
    }

    private func headerButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        HeaderIconButton(icon: icon, help: help, action: action)
    }
    @ViewBuilder
    private var prContent: some View {
        if !store.isConfigured {
            OnboardingView {
                withAnimation(.snappy(duration: 0.2)) { page = .settings }
            }
        } else if store.isLoading && store.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text("Fetching pull requests...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.error {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Something went wrong",
                subtitle: error,
                action: ("Retry", { store.refresh() })
            )
        } else {
            tabContent
        }
    }
    private var tabContent: some View {
        VStack(spacing: 0) {
            if let prUrl = addingToFeaturePR {
                featurePickerBar(for: prUrl)
            } else if let featureId = renamingFeatureId {
                HeaderInputBar(
                    label: "Rename:",
                    text: $renameText,
                    action: "Save",
                    onSubmit: { saveRename(featureId: featureId) },
                    onCancel: { withAnimation(.snappy(duration: 0.2)) { renamingFeatureId = nil } }
                )
            } else if let confirm = confirmState {
                HeaderConfirmBar(
                    message: confirm.message,
                    action: confirm.action,
                    isDestructive: confirm.isDestructive,
                    onConfirm: {
                        confirm.handler()
                        withAnimation(.snappy(duration: 0.2)) { confirmState = nil }
                    },
                    onCancel: { withAnimation(.snappy(duration: 0.2)) { confirmState = nil } }
                )
            } else if promotingBranch != nil {
                HeaderInputBar(
                    label: "Feature name:",
                    text: $promoteName,
                    action: "Create",
                    onSubmit: { commitPromote() },
                    onCancel: { withAnimation(.snappy(duration: 0.2)) { promotingBranch = nil } }
                )
            }

            ZStack {
                ForEach(enabledTabs, id: \.self) { tab in
                    if tab == .features {
                        FeaturesListView(
                            features: $features,
                            allPulls: allPulls,
                            config: displayConfig,
                            expandedPRUrl: $expandedPRUrl,
                            onRename: { id in
                                let name = features.first(where: { $0.id == id })?.name ?? ""
                                withAnimation(.snappy(duration: 0.2)) {
                                    renameText = name
                                    renamingFeatureId = id
                                }
                            },
                            onPromote: { branch, edges in
                                withAnimation(.snappy(duration: 0.2)) {
                                    promoteName = branch.components(separatedBy: "/").last ?? branch
                                    promoteEdges = edges
                                    promotingBranch = branch
                                }
                            },
                            onConfirm: { message, action, destructive, handler in
                                showConfirm(message: message, action: action, isDestructive: destructive, handler: handler)
                            }
                        )
                        .opacity(selectedTab == .features ? 1 : 0)
                        .allowsHitTesting(selectedTab == .features)
                        .accessibilityHidden(selectedTab != .features)
                    } else {
                        PRListView(
                            edges: pulls(for: tab),
                            tabName: tab.rawValue,
                            config: displayConfig,
                            expandedPRUrl: $expandedPRUrl,
                            searchText: $searchText,
                            onAddToFeature: { prUrl in
                                withAnimation(.snappy(duration: 0.2)) {
                                    addingToFeaturePR = prUrl
                                }
                            }
                        )
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                        .accessibilityHidden(selectedTab != tab)
                    }
                }
            }
        }
    }
    private func featurePickerBar(for prUrl: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isCreatingFeature {
                    Text("Name:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Feature name...", text: $newFeatureName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: 150)
                        .onSubmit { commitNewFeature(withPR: prUrl) }
                    Button {
                        commitNewFeature(withPR: prUrl)
                    } label: {
                        Text("Add")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.tabSelected, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(newFeatureName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Text("Add to:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(features.filter { !$0.prURLs.contains(prUrl) }) { feature in
                                Button {
                                    addPRToFeature(prUrl: prUrl, featureId: feature.id)
                                } label: {
                                    Text(feature.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.cardBackground, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                withAnimation(.snappy(duration: 0.15)) {
                                    isCreatingFeature = true
                                    newFeatureName = ""
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("New")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.tabSelected, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        addingToFeaturePR = nil
                        isCreatingFeature = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.headerPaddingH)
            .padding(.vertical, 6)

            Divider().opacity(0.5)
        }
        .background(Theme.cardBackground)
    }

    private func addPRToFeature(prUrl: String, featureId: UUID) {
        if let idx = features.firstIndex(where: { $0.id == featureId }) {
            if !features[idx].prURLs.contains(prUrl) {
                features[idx].prURLs.append(prUrl)
            }
        }
        withAnimation(.snappy(duration: 0.2)) {
            addingToFeaturePR = nil
        }
    }

    private func commitNewFeature(withPR prUrl: String) {
        let name = newFeatureName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var feature = PRFeature(name: name)
        feature.prURLs = [prUrl]
        features.append(feature)
        withAnimation(.snappy(duration: 0.2)) {
            addingToFeaturePR = nil
            isCreatingFeature = false
            newFeatureName = ""
        }
    }

    private func saveRename(featureId: UUID) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let idx = features.firstIndex(where: { $0.id == featureId }) {
            features[idx].name = name
        }
        withAnimation(.snappy(duration: 0.2)) { renamingFeatureId = nil }
    }

    private func showConfirm(message: String, action: String, isDestructive: Bool, handler: @escaping () -> Void) {
        withAnimation(.snappy(duration: 0.2)) {
            confirmState = ConfirmState(message: message, action: action, isDestructive: isDestructive, handler: handler)
        }
    }

    private func commitPromote() {
        let name = promoteName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var feature = PRFeature(name: name)
        feature.prURLs = promoteEdges.map { $0.node.url.absoluteString }
        features.append(feature)
        withAnimation(.snappy(duration: 0.2)) {
            promotingBranch = nil
            promoteEdges = []
            promoteName = ""
        }
    }
}
