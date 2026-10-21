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
                HStack(spacing: Spacing.m) {
                    Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                    Text("Morning brief").fontWeight(.medium)
                    Text(snapshot.day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(snapshot.waitingForReview) for review · \(snapshot.quietOwned) of yours quiet").foregroundStyle(Palette.textSecondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.ui(Typography.caption2, .semibold)).foregroundStyle(Palette.textSecondary)
                }.font(.ui(Typography.callout)).padding(.horizontal, Spacing.xl).frame(height: Layout.briefHeaderHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Morning brief")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                if snapshot.entries.isEmpty {
                    Text(emptyMessage)
                        .font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, minHeight: Layout.briefEmptyHeight)
                } else {
                    ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        Button { select(entry.id) } label: {
                            HStack(alignment: .center, spacing: Spacing.xl) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(verbatim: "\(entry.repository) #\(entry.number) · \(entry.title)").font(.ui(Typography.callout, .medium)).lineLimit(1)
                                    Text(notes.indices.contains(index) ? notes[index] : entry.reason)
                                        .font(.ui(Typography.subheadline)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.action).font(.ui(Typography.footnote, .medium)).foregroundStyle(Palette.accent)
                                    .lineLimit(2).frame(width: Layout.briefActionWidth, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.ui(Typography.caption2)).foregroundStyle(Palette.textTertiary)
                            }.padding(.horizontal, Spacing.xl).frame(height: Layout.briefRowHeight).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(entry.reason)
                            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
                    }
                    HStack(spacing: Spacing.s) {
                        if generating { ProgressView().controlSize(.mini) }
                        Text(generating ? "Preparing explanations on this Mac…" : (error ?? "Explanations by Apple Intelligence · Based on PR status and quiet time"))
                            .font(.ui(Typography.caption)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                        Spacer(minLength: 0)
                        if error != nil, PRIntelligenceService.unavailableMessage == nil { Button("Retry") { retry += 1 }.font(.ui(Typography.footnote)) }
                    }.padding(.horizontal, Spacing.xl).frame(height: Layout.briefFooterHeight)
                }
            }
        }.background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.line))
            .clipShape(RoundedRectangle(cornerRadius: Radius.l))
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
