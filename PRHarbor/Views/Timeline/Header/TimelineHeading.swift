import SwiftUI

struct TimelineHeading: View {
    let items: [TimelineItem]
    let now: Date
    @Binding var tab: TimelineTab
    @Binding var range: Int
    @Binding var sortOrder: SortOrder
    let store: PullRequestStore
    var isPreview = false
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    private var created: Binding<Bool> {
        Binding(get: { sortOrder == .createdNewest || sortOrder == .createdOldest }, set: { sortOrder = $0 ? .createdNewest : .updatedNewest })
    }
    var body: some View {
        HStack(spacing: Spacing.l) {
            SegmentedControl(label: "Pull requests", selection: $tab, options: TimelineTab.allCases.map { tab in
                (tab, tab.rawValue, items.filter { tab == .all || (tab == .mine ? $0.isMine : !$0.isMine) }.count)
            })
            Button { if !isPreview { store.refresh() } } label: {
                HStack(spacing: Spacing.s) {
                    Circle().fill(syncColor).frame(width: Size.statusDot, height: Size.statusDot)
                    Text(isPreview ? "Mock data" : syncLabel)
                }
            }
            .buttonStyle(.badge(syncColor, background: isPreview ? Palette.track : syncColor.opacity(Opacity.badge)))
            .help("Refresh from GitHub (⌘R)")
            Spacer(minLength: 0)
            SegmentedControl(label: "Sort", selection: created, options: [(false, "Updated", nil), (true, "Created", nil)])
            SegmentedControl(label: "Timeline range", selection: $range, options: [(14, "2W", nil), (30, "1M", nil), (90, "3M", nil), (182, "6M", nil)])
            Button(action: onSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.icon(size: Size.iconButton, symbolSize: Typography.iconLarge)).help("Settings (⌘,)").accessibilityLabel("Settings").keyboardShortcut(",")
                .contextMenu { Button("Refresh") { store.refresh() }; Button("About PR Harbor", action: onAbout); Button("Quit PR Harbor", action: onQuit) }
        }.padding(.horizontal, Spacing.panel).padding(.top, Spacing.xxxl).padding(.bottom, Spacing.s)
        .background {
            Button("Refresh") { store.refresh() }.keyboardShortcut("r").hidden().accessibilityHidden(true)
        }
    }
    private var syncColor: Color {
        if isPreview || store.isLoading { return Palette.textSecondary }
        if store.error != nil { return Palette.failure }
        return Freshness.fresh.label
    }
    private var syncLabel: String {
        if store.isLoading { return "Syncing…" }
        if store.error != nil { return "Sync failed" }
        guard let date = store.lastSyncedAt else { return "Live" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return (store.isShowingCache ? (store.hasIncompleteData ? "Cached · partial · " : "Cached · ") : "Live · ") + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m ago" : minutes < 1440 ? "\(Int((Double(minutes) / 60).rounded()))h ago" : "\(Int((Double(minutes) / 1440).rounded()))d ago")
    }
}
