import Defaults
import SwiftUI

struct TimelineRow: View {
    let item: TimelineItem
    let scale: TimelineScale
    let now: Date
    let selected: Bool
    var layer: Bool = false
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack(spacing: 0) {
                HStack(spacing: Spacing.l) {
                    TimelineAvatar(person: item.pull.author, size: Size.avatar)
                        .accessibilityHidden(true)
                        .overlay(alignment: .bottomTrailing) {
                            if layer, let position = item.pull.stackEntry?.position {
                                Text("\(position)").font(.ui(Typography.micro, .bold)).foregroundStyle(Palette.textSecondary)
                                    .frame(minWidth: Size.positionBadge).frame(height: Size.positionBadge).background(Palette.raised, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Palette.strong)).offset(Layout.positionBadgeOffset)
                            }
                        }
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(item.title).font(.ui(Typography.body, .medium)).lineLimit(1)
                        HStack(spacing: Spacing.xs) {
                            Text(verbatim: "#\(item.pull.number)")
                            if let detail = item.isMine ? item.ticket : item.pull.author?.login { Text("·"); Text(detail).lineLimit(1) }
                            if item.pull.isDraft { Text("· draft") }
                            if item.snoozedUntil != nil { Image(systemName: "moon.zzz") }
                        }
                        .font(.ui(Typography.subheadline)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Spacing.xxl)
                .frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                TimelineTrack(item: item, scale: scale, now: now, fixedWidth: TimelineMetrics.trackWidth)
            }
            .frame(height: layer ? TimelineRowGeometry.layerHeight : TimelineRowGeometry.pullHeight)
            .modifier(TimelineRowHighlight(selected: selected))
            .opacity(item.snoozedUntil == nil ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.pull.title + "\n" + item.standing)
        .accessibilityAction(named: Text("Show history")) { Defaults[.detailHistory] = true; select() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            Link("Open on GitHub", destination: item.pull.url)
            Button("Copy branch name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.pull.headRefName, forType: .string)
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.id, forType: .string)
            }
        }
    }
}

/// Moving rows under the pointer changes only the highlight, not the track's
/// event layout, tooltips, and avatar subtree.
private struct TimelineRowHighlight: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(selected ? Palette.accentSoft : hovering ? Palette.hover : .clear)
                .padding(.vertical, Spacing.xxxs).padding(.horizontal, -Spacing.m)
        }
        .onHover { if hovering != $0 { hovering = $0 } }
    }
}
