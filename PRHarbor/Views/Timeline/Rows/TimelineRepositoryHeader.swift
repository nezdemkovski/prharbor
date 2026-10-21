import SwiftUI

struct TimelineRepositoryHeader: View {
    let name: String
    let items: [TimelineItem]
    let scale: TimelineScale
    let collapsed: Bool
    var showOwner = false
    let toggle: () -> Void
    var body: some View {
        // Only the label column toggles; the timeline beside it belongs to the timeline pointer.
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.ui(Typography.micro, .semibold)).frame(
                        width: Size.disclosure)
                    if name == "Bots" { Image(systemName: "gearshape.2") }
                    HStack(spacing: 0) {
                        if showOwner, name.contains("/"), let owner = name.split(separator: "/").first {
                            Text(String(owner) + "/").fontWeight(.medium).foregroundStyle(Palette.textTertiary)
                        }
                        Text(name == "Bots" ? name : String(name.split(separator: "/").last ?? ""))
                    }.lineLimit(1)
                    Text("\(items.count)").foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .font(.ui(Typography.callout, .semibold)).foregroundStyle(Palette.textSecondary)
                .frame(width: TimelineMetrics.labelWidth, alignment: .leading).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(items.count) pull requests, \(collapsed ? "collapsed" : "expanded")")
            GeometryReader { geometry in
                if collapsed {
                    ForEach(items.filter(\.hasKnownQuietPeriod)) { item in
                        Circle().fill(item.freshness.fill).frame(width: Size.dot, height: Size.dot)
                            .position(
                                x: max(
                                    Layout.collapsedDotInset,
                                    min(
                                        geometry.size.width - Layout.collapsedDotInset,
                                        scale.position(age: item.quietDays) * geometry.size.width)), y: Layout.trackHeight / 2)
                    }
                }
            }
        }
        .frame(height: TimelineRowGeometry.repositoryHeight - 6).padding(.top, Spacing.s)
    }
}
