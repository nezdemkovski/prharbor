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
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(!item.isBlocked && item.hasKnownQuietPeriod ? item.freshness.color : TimelineStyle.muted).frame(width: 8, height: 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13.5, weight: .semibold)).tracking(-0.0675)
                        .lineLimit(1).frame(height: 18, alignment: .leading).textSelection(.enabled)
                    facts
                }.frame(maxWidth: .infinity, alignment: .leading)
                detailTools
            }
            if showHistory {
                HStack(spacing: 10) {
                    Text(item.pull.createdAt, format: .dateTime.month(.abbreviated).day()).fixedSize()
                    TimelineTrack(item: item, scale: TimelineScale(days: max(1, Int(ceil(item.age * 1.04)))), now: now).scaleEffect(x: 1, y: 0.65).frame(height: 22)
                    HStack(spacing: 3) { Text("today ·"); Text(item.hasKnownQuietPeriod ? "\(TimelinePolicy.duration(item.quietDays)) quiet" : "quiet time unknown").fontWeight(.semibold).foregroundStyle(item.hasKnownQuietPeriod ? item.freshness.color : TimelineStyle.muted) }.fixedSize()
                }.font(.system(size: 11)).foregroundStyle(TimelineStyle.faint).padding(.leading, 18)
                if item.pull.timelineItems?.pageInfo?.hasPreviousPage == true {
                    Text("Showing the latest 60 events. Full history is available on GitHub.").font(.caption2).foregroundStyle(TimelineStyle.muted)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(TimelineStyle.muted).textSelection(.enabled) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .background(TimelineStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TimelineStyle.strong))
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
    private var primaryLabel: String {
        switch item.nextAction {
        case "Ask for review": "Request review"
        case "Nudge reviewers": "Nudge"
        case "Continue draft": "Mark ready"
        case "Open on GitHub": item.isMine ? "In review" : "Open"
        default: item.nextAction.replacingOccurrences(of: " on GitHub", with: "")
        }
    }
    private var facts: some View {
        HStack(spacing: 0) {
            Text(verbatim: "#\(item.pull.number)" + (item.isMine ? "" : " · \(item.pull.author?.login ?? "ghost")")).fixedSize()
            if !item.pull.headRefName.isEmpty {
            separator
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(TimelineStyle.faint)
                Text(item.pull.headRefName).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.pull.headRefName, forType: .string); copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)).frame(width: 18, height: 18).foregroundStyle(TimelineStyle.faint) }
                    .buttonStyle(.plain).help("Copy branch name").accessibilityLabel("Copy branch name")
                    .task(id: copied) { guard copied else { return }; try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copied = false } }
            }.frame(minWidth: 90, maxWidth: 160)
            }
            separator
            Text(detailStatus).lineLimit(1)
            if !item.checks.isEmpty || item.ci != nil { separator; checksSummary }
            if let target = item.pull.baseRefName ?? item.pull.stack?.baseRefName {
                separator
                Text("→ \(target)").font(.system(size: 11.5, weight: .medium, design: .monospaced)).lineLimit(1)
            }
        }.font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted).frame(height: 18).clipped()
    }
    private var separator: some View { Text("·").foregroundStyle(TimelineStyle.faint).padding(.horizontal, 7) }
    private var detailTools: some View {
        HStack(spacing: 2) {
            tool("clock", label: showHistory ? "Hide history" : "Show history") { showHistory.toggle() }
            tool("arrow.up.right.square", label: "Open on GitHub (O)") { openURL(item.pull.url) }
            if item.pull.stack == nil || item.pull.stack?.size == 1 {
                Menu {
                    if item.snoozedUntil != nil { Button("Wake up") { wake() } }
                    else { Button("Tomorrow") { snooze(days: 1) }; Button("In 3 days") { snooze(days: 3) }; Button("Next week") { snooze(days: 7) } }
                } label: { Image(systemName: "moon").font(.system(size: 15)).foregroundStyle(TimelineStyle.muted).frame(width: 28, height: 28) }
                .tint(TimelineStyle.muted).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Snooze (S)").accessibilityLabel("Snooze")
            }
            if item.isMine { tool("xmark", label: "Close on GitHub") { openURL(item.pull.url) } }
            Button(action: primary) {
                HStack(spacing: 5) { Text(primaryLabel); Text("⏎").opacity(0.7) }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(TimelineStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }.buttonStyle(.plain).disabled(rebasing).padding(.leading, 8)
                .help(!item.isBlocked ? "Continue on GitHub (Return)" : "Select the base pull request (Return)")
                .contextMenu {
                    if item.pull.stack != nil { Button("Rebase stack…") { confirmRebase = true }.disabled(rebasing) }
                }
        }.fixedSize()
    }
    private func tool(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(TimelineStyle.muted).frame(width: 28, height: 28) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    @ViewBuilder private var checksSummary: some View {
        let failures = item.checks.filter { ciStatusKind($0.status) == .failure }
        if let check = failures.first {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle").foregroundStyle(Freshness.rotting.color)
                Text(check.name + (failures.count > 1 ? " +\(failures.count - 1)" : "")).lineLimit(1).foregroundStyle(Freshness.rotting.color)
                if let url = check.url { Link("Open log ↗", destination: url).foregroundStyle(TimelineStyle.text) }
            }
        } else if item.ci == .failure {
            SwiftUI.Label("Checks failed", systemImage: "xmark.circle").foregroundStyle(Freshness.rotting.color)
                .help("A failing check is outside the loaded details. Open GitHub for all checks.")
        } else if item.ci == .pending {
            SwiftUI.Label("Checks running", systemImage: "clock").foregroundStyle(Freshness.aging.color)
        } else if item.ci == .success {
            SwiftUI.Label("Checks passed", systemImage: "checkmark.circle").foregroundStyle(Freshness.fresh.color)
        } else {
            SwiftUI.Label("Check status unknown", systemImage: "questionmark.circle").foregroundStyle(TimelineStyle.muted)
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
