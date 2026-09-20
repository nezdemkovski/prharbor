
import SwiftUI
import Defaults

enum PRTab: String, CaseIterable {
    case reviewRequested = "Review Requested"
    case assigned = "Assigned"
    case created = "My PRs"
}

enum PanelPage {
    case main
    case settings
    case about
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
    @State private var selectedTab: PRTab = .reviewRequested
    @State private var expandedPRUrl: String?
    @State private var page: PanelPage = .main
    @State private var showQuitConfirmation = false
    @State private var searchText = ""
    @State private var isSearching = false

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

    private func pulls(for tab: PRTab) -> [Edge] {
        switch tab {
        case .reviewRequested: store.reviewRequestedPulls
        case .assigned: store.assignedPulls
        case .created: store.createdPulls
        }
    }

    private func count(for tab: PRTab) -> Int {
        pulls(for: tab).count
    }

    private func isTabEnabled(_ tab: PRTab) -> Bool {
        switch tab {
        case .reviewRequested: Defaults[.showRequested]
        case .assigned: Defaults[.showAssigned]
        case .created: Defaults[.showCreated]
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
        .onChange(of: enabledTabs) { _, tabs in
            guard !tabs.contains(selectedTab), let firstTab = tabs.first else { return }
            selectedTab = firstTab
            expandedPRUrl = nil
        }
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
    @ViewBuilder
    private var tabContent: some View {
        if enabledTabs.isEmpty {
            EmptyStateView(
                icon: "rectangle.on.rectangle.slash",
                title: "No tabs enabled",
                subtitle: "Enable at least one tab in Settings"
            )
        } else {
            enabledTabContent
        }
    }

    private var enabledTabContent: some View {
        ZStack {
            ForEach(enabledTabs, id: \.self) { tab in
                PRListView(
                    edges: pulls(for: tab),
                    tabName: tab.rawValue,
                    config: displayConfig,
                    expandedPRUrl: $expandedPRUrl,
                    searchText: $searchText,
                    onRebaseStack: { stack in
                        try await store.rebaseStack(stack)
                    }
                )
                .opacity(selectedTab == tab ? 1 : 0)
                .allowsHitTesting(selectedTab == tab)
                .accessibilityHidden(selectedTab != tab)
            }
        }
    }
}
