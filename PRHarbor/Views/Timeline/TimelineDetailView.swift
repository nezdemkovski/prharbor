import SwiftUI
import Defaults

struct TimelineDetailView: View {
    let item: TimelineItem
    let now: Date
    let store: PullRequestStore
    let select: (String) -> Void
    var availableURLs: Set<String> = []
    @Default(.detailHistory) private var showHistory
    @Default(.snoozedPulls) private var snoozed
    @Default(.snoozeActivity) private var snoozeActivity
    @State private var copied = false
    @State private var confirmRebase = false
    @State private var rebasing = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.l) {
                Circle().fill(!item.isBlocked && item.hasKnownQuietPeriod ? item.freshness.fill : Palette.textSecondary).frame(width: Size.detailDot, height: Size.detailDot).padding(.top, Spacing.s)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(item.title).font(.ui(Typography.headline, .semibold)).tracking(-0.0675)
                        .lineLimit(1).frame(height: Layout.detailLineHeight, alignment: .leading).textSelection(.enabled)
                    facts
                }.frame(maxWidth: .infinity, alignment: .leading)
                detailTools
            }
            if showHistory {
                HStack(spacing: Spacing.l) {
                    Text(item.pull.createdAt, format: .dateTime.month(.abbreviated).day()).fixedSize()
                    TimelineTrack(item: item, scale: TimelineScale(days: max(1, Int(ceil(item.age * 1.04)))), now: now).scaleEffect(x: 1, y: 0.65).frame(height: Layout.historyTrackHeight)
                    HStack(spacing: Spacing.xxs) { Text("today ·"); Text(item.hasKnownQuietPeriod ? "\(TimelinePolicy.duration(item.quietDays)) quiet" : "quiet time unknown").fontWeight(.semibold).foregroundStyle(item.hasKnownQuietPeriod ? item.freshness.label : Palette.textSecondary) }.fixedSize()
                }.font(.ui(Typography.footnote)).foregroundStyle(Palette.textTertiary).padding(.leading, Spacing.panel)
                if item.pull.timelineItems?.pageInfo?.hasPreviousPage == true {
                    Text("Showing the latest 60 events. Full history is available on GitHub.").font(.caption2).foregroundStyle(Palette.textSecondary)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled) }
        }
        .padding(.horizontal, Spacing.xxxl).padding(.top, Spacing.xxl).padding(.bottom, Spacing.xl)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.strong))
        .alert("Rebase this stack?", isPresented: $confirmRebase) {
            Button("Cancel", role: .cancel) {}
            Button("Rebase") { rebase() }
        } message: {
            Text("Updates \(item.pull.stack?.size ?? 0) branches on GitHub onto \(item.pull.stack?.baseRefName ?? "the base branch").")
        }
        .onChange(of: item.id) { _, _ in copied = false; message = nil }
    }

    private var detailStatus: String {
        if item.isBlocked, let base = item.blockedBy { return "waits for #\(base.number)" }
        if let until = item.snoozedUntil { return "snoozed till \(until.formatted(.dateTime.month(.abbreviated).day()))" }
        if !item.hasKnownQuietPeriod { return "quiet time unknown" }
        if item.quietDays < 1 { return "active today" }
        return item.isMine ? "\(TimelinePolicy.duration(item.quietDays)) quiet" : "waiting \(TimelinePolicy.duration(item.quietDays)) on you"
    }
    private var primaryLabel: String { item.nextAction.buttonTitle(isMine: item.isMine) }
    private var facts: some View {
        HStack(spacing: 0) {
            Text(verbatim: "#\(item.pull.number)" + (item.isMine ? "" : " · \(item.pull.author?.login ?? "ghost")")).fixedSize()
            if !item.pull.headRefName.isEmpty {
            separator
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch").font(.ui(Typography.footnote)).foregroundStyle(Palette.textTertiary)
                Text(item.pull.headRefName).font(.ui(Typography.footnote, .medium, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.pull.headRefName, forType: .string); copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.icon(size: Size.smallButton, symbolSize: Typography.footnote, color: Palette.textTertiary)).help("Copy branch name").accessibilityLabel("Copy branch name")
                    .task(id: copied) { guard copied else { return }; try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copied = false } }
            }.frame(minWidth: Layout.branchMinWidth, maxWidth: Layout.branchMaxWidth)
            }
            separator
            Text(detailStatus).lineLimit(1)
            if !item.checks.isEmpty || item.ci != nil { separator; checksSummary }
            if let target = item.pull.baseRefName ?? item.pull.stack?.baseRefName {
                separator
                Text("→ \(target)").font(.ui(Typography.subheadline, .medium, design: .monospaced)).lineLimit(1)
            }
        }.font(.ui(Typography.subheadline)).foregroundStyle(Palette.textSecondary).frame(height: Layout.detailLineHeight).clipped()
    }
    private var separator: some View { Text("·").foregroundStyle(Palette.textTertiary).padding(.horizontal, Spacing.s) }
    private var detailTools: some View {
        HStack(spacing: Spacing.xxxs) {
            tool("clock", label: showHistory ? "Hide history" : "Show history") { showHistory.toggle() }
            tool("arrow.up.right.square", label: "Open on GitHub (O)") { openURL(item.pull.url) }
            if item.pull.stack == nil || item.pull.stack?.size == 1 {
                Menu {
                    if item.snoozedUntil != nil { Button("Wake up") { wake() } }
                    else { Button("Tomorrow") { snooze(days: 1) }; Button("In 3 days") { snooze(days: 3) }; Button("Next week") { snooze(days: 7) } }
                } label: { Image(systemName: "moon") }
                .menuStyle(.button).buttonStyle(.icon).menuIndicator(.hidden).fixedSize().help("Snooze (S)").accessibilityLabel("Snooze")
            }
            if item.isMine { tool("xmark", label: "Close on GitHub") { openURL(item.pull.url) } }
            Button(action: primary) {
                HStack(spacing: Spacing.xs) { Text(primaryLabel); Text("⏎").opacity(Opacity.deemphasized) }
            }.buttonStyle(.primary).disabled(rebasing).padding(.leading, Spacing.m)
                .help(!item.isBlocked ? "Continue on GitHub (Return)" : "Select the base pull request (Return)")
                .contextMenu {
                    if item.pull.stack != nil { Button("Rebase stack…") { confirmRebase = true }.disabled(rebasing) }
                }
        }.fixedSize()
    }
    private func tool(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.icon).help(label).accessibilityLabel(label)
    }
    @ViewBuilder private var checksSummary: some View {
        let failures = item.checks.filter { ciStatusKind($0.status) == .failure }
        if let check = failures.first {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "xmark.circle").foregroundStyle(Palette.failure)
                Text(check.name + (failures.count > 1 ? " +\(failures.count - 1)" : "")).lineLimit(1).foregroundStyle(Palette.failure)
                if let url = check.url { Link("Open log ↗", destination: url).foregroundStyle(Palette.textPrimary) }
            }
        } else if item.ci == .failure {
            SwiftUI.Label("Checks failed", systemImage: "xmark.circle").foregroundStyle(Palette.failure)
                .help("A failing check is outside the loaded details. Open GitHub for all checks.")
        } else if item.ci == .pending {
            SwiftUI.Label("Checks running", systemImage: "clock").foregroundStyle(Palette.warning)
        } else if item.ci == .success {
            SwiftUI.Label("Checks passed", systemImage: "checkmark.circle").foregroundStyle(Palette.success)
        } else {
            SwiftUI.Label("Check status unknown", systemImage: "questionmark.circle").foregroundStyle(Palette.textSecondary)
        }
    }
    private func primary() {
        if item.isBlocked, let base = item.blockedBy {
            if availableURLs.contains(base.url.absoluteString) { select(base.url.absoluteString) } else { openURL(base.url) }
        }
        else { openURL(item.pull.url) }
    }
    private func snooze(days: Int) {
        snoozed[item.id] = Calendar.current.date(byAdding: .day, value: days, to: now)?.timeIntervalSince1970
        snoozeActivity[item.id] = now.timeIntervalSince1970
    }
    private func wake() { snoozed.removeValue(forKey: item.id); snoozeActivity.removeValue(forKey: item.id) }
    private func rebase() {
        guard let stack = item.pull.stack else { return }
        rebasing = true; message = nil
        Task { @MainActor in
            defer { rebasing = false }
            do {
                let result = try await store.rebaseStack(stack)
                message = "Rebased \(result.rebasedCount) of \(result.totalCount) layers."
            } catch { message = error.localizedDescription }
        }
    }
}
