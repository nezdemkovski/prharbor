#if DEBUG
import Defaults
import SwiftUI
#endif

#if DEBUG
#Preview("PR timeline") {
    let store = PullRequestStore(startAutomatically: false)
    let now = Date()
    TimelinePanel(store: store, now: now, onSettings: {}, onAbout: {}, onQuit: {}, previewItems: TimelinePreviewData.items(now: now))
        .frame(width: TimelineMetrics.panelWidth)
}
#endif

#if DEBUG
struct TimelinePreviewHost: View {
    let store: PullRequestStore
    @Environment(\.openSettings) private var openSettings
    @State private var now = Date()
    @Default(.snoozedPulls) private var snoozed
    @Default(.freshnessThresholds) private var thresholds
    @Default(.ownCommentsCount) private var comments
    @Default(.botAccounts) private var bots
    @Default(.hideDrafts) private var hideDrafts
    @Default(.showCreated) private var showCreated
    @Default(.showRequested) private var showRequested
    private var items: [TimelineItem] {
        TimelinePreviewData.items(now: now).filter { ($0.isMine ? showCreated : showRequested) && (!hideDrafts || !$0.pull.isDraft) }.map { item in
            TimelineItem(pull: item.pull, username: TimelinePreviewData.username, now: now, thresholds: thresholds,
                         bots: bots, ownComments: comments,
                         snoozedUntil: snoozed[item.id].map { Date(timeIntervalSince1970: $0) } ?? item.snoozedUntil, reviewRequested: item.reviewRequested)
        }
    }
    var body: some View {
        TimelinePanel(store: store, now: now, onSettings: { openSettings() }, onAbout: {}, onQuit: { NSApp.terminate(nil) }, previewItems: items)
            .frame(width: TimelineMetrics.panelWidth)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                let items = TimelinePreviewData.items(now: now)
                store.createdPulls = items.filter(\.isMine).map { Edge(node: $0.pull) }
                store.reviewRequestedPulls = items.filter { !$0.isMine }.map { Edge(node: $0.pull) }
                NSApp.activate()
            }
    }
}
#endif
