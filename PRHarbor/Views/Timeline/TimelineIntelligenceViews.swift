import SwiftUI
import Defaults

struct TimelineMorningBrief: View {
    let snapshot: MorningBriefSnapshot
    @Binding var expanded: Bool
    let select: (String) -> Void
    var emptyMessage = "All clear. No pull requests need attention right now."
    @State private var notes: [String] = []
    @State private var error: String?
    @State private var generating = false
    @State private var retry = 0
    private struct Request: Equatable { let snapshot: MorningBriefSnapshot; let expanded: Bool; let retry: Int }
    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(TimelineStyle.accent)
                    Text("Morning brief").fontWeight(.medium)
                    Text(snapshot.day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(TimelineStyle.muted)
                    Spacer()
                    Text("\(snapshot.waitingForReview) for review · \(snapshot.quietOwned) of yours quiet").foregroundStyle(TimelineStyle.muted)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(TimelineStyle.muted)
                }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Morning brief")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                if snapshot.entries.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 12)).foregroundStyle(TimelineStyle.muted).frame(maxWidth: .infinity, minHeight: 52)
                } else {
                    ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        Button { select(entry.id) } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: "\(entry.repository) #\(entry.number) · \(entry.title)").font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(notes.indices.contains(index) ? notes[index] : entry.reason)
                                        .font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.action).font(.system(size: 11, weight: .medium)).foregroundStyle(TimelineStyle.accent)
                                    .lineLimit(2).frame(width: 108, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(TimelineStyle.faint)
                            }.padding(.horizontal, 12).frame(height: 74).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(entry.reason)
                            .overlay(alignment: .top) { Rectangle().fill(TimelineStyle.line).frame(height: 1) }
                    }
                    HStack(spacing: 6) {
                        if generating { ProgressView().controlSize(.mini) }
                        Text(generating ? "Preparing explanations on this Mac…" : (error ?? "Explanations by Apple Intelligence · Based on PR status and quiet time"))
                            .font(.system(size: 10.5)).foregroundStyle(TimelineStyle.muted).lineLimit(2)
                        Spacer(minLength: 0)
                        if error != nil, PRIntelligenceService.unavailableMessage == nil { Button("Retry") { retry += 1 }.font(.system(size: 11)) }
                    }.padding(.horizontal, 12).frame(height: 44)
                }
            }
        }.background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TimelineStyle.line))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: Request(snapshot: snapshot, expanded: expanded, retry: retry)) {
                notes = []; error = nil; generating = false
                guard expanded, !snapshot.entries.isEmpty else { return }
                if let message = PRIntelligenceService.unavailableMessage { error = message; return }
                generating = true
                do {
                    let result = try await PRIntelligenceService.shared.morningBrief(snapshot)
                    guard !Task.isCancelled, Defaults[.intelligentMorningBrief] else { return }
                    notes = result
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = PRIntelligenceService.message(for: error)
                }
                generating = false
            }
    }
}

struct IntelligenceSettings: View {
    @Default(.intelligentSearch) private var search
    @Default(.intelligentMorningBrief) private var morning
    var body: some View {
        VStack(spacing: 0) {
            TimelineSettingsRow("Natural language search", hint: "Type a phrase in the existing search field. Results update automatically; regular searches stay instant.") {
                Toggle("Natural language search", isOn: $search).labelsHidden().toggleStyle(TimelineSwitchStyle())
            }
            TimelineSettingsRow("Morning brief", hint: "An optional overview of up to three PRs. Expand it to generate short explanations.") {
                Toggle("Morning brief", isOn: $morning).labelsHidden().toggleStyle(TimelineSwitchStyle())
            }
            VStack(alignment: .leading, spacing: 6) {
                SwiftUI.Label("Runs on this Mac", systemImage: "desktopcomputer").font(.system(size: 12, weight: .medium))
                Text("Uses Apple's on-device model. Both features are off by default and do not change regular search or morning notifications.")
                if let message = PRIntelligenceService.unavailableMessage { Text(message) }
            }.font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
