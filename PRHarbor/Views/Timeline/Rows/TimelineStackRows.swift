import Defaults
import SwiftUI

struct TimelineStackRows: View {
    let group: PullDisplayGroup
    let items: [TimelineItem]
    let scale: TimelineScale
    let now: Date
    let selection: String?
    let isCollapsed: Bool
    let select: (String) -> Void
    let toggle: () -> Void
    @Default(.mergedLayersStyle) private var mergedStyle
    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                Button(action: toggle) {
                    HStack(spacing: 0) {
                        SwiftUI.Label("Stack · \(items.count) layers", systemImage: "square.3.layers.3d")
                            .font(.ui(Typography.callout, .medium)).frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                        VStack(spacing: TimelineRowGeometry.collapsedBarSpacing) {
                            ForEach(items) { item in
                                GeometryReader { geometry in
                                    let start = scale.position(age: item.age) * geometry.size.width
                                    Capsule().fill((item.hasKnownQuietPeriod ? item.freshness.fill : Palette.textTertiary).opacity(Opacity.quietBar)).frame(width: max(2, geometry.size.width - start)).offset(x: start)
                                }.frame(height: TimelineRowGeometry.collapsedBarHeight)
                            }
                        }
                    }
                    .frame(height: TimelineRowGeometry.collapsedBodyHeight(layers: items.count))
                    .padding(TimelineRowGeometry.collapsedContentPadding)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                ForEach(items) { item in
                    TimelineRow(item: item, scale: scale, now: now, selected: selection == item.id, layer: true) { select(item.id) }.id(item.id)
                }
            }
            Button(action: toggle) {
                HStack(spacing: Spacing.l) {
                    Image(systemName: "arrow.triangle.branch").font(.ui(Typography.footnote)).frame(width: Size.chip, height: Size.chip)
                        .background(Palette.raised, in: Circle()).overlay(Circle().strokeBorder(Palette.strong))
                        .padding(.horizontal, Spacing.xs)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(group.stack?.baseRefName ?? "base").font(.ui(Typography.subheadline, .semibold, design: .monospaced))
                        if mergedStyle != .hidden, let entries = group.stack?.entries?.nodes {
                            let merged = entries.compactMap(\.pullRequest).filter { $0.state == .merged }
                            if !merged.isEmpty {
                                Text("· " + (mergedStyle == .count ? "\(merged.count) merged" : merged.map { "#\($0.number)" }.joined(separator: " ")))
                                    .font(.ui(Typography.footnote)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                                    .help(merged.map { "#\($0.number) \($0.title)" }.joined(separator: "\n"))
                            }
                        }
                    }
                    Spacer()
                }.foregroundStyle(Palette.textSecondary).frame(height: Layout.stackFooterHeight)
                    .frame(height: TimelineRowGeometry.stackFooterHeight, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(.plain).help(isCollapsed ? "Expand stack" : "Collapse stack")
        }
        .background(alignment: .topLeading) {
            if !isCollapsed {
                TimelineLiquidRail(layers: items.count).frame(width: Layout.stackRailWidth, height: CGFloat(items.count) * TimelineRowGeometry.layerHeight + TimelineRowGeometry.stackFooterHeight).offset(x: -6)
            }
        }
        .padding(.vertical, TimelineRowGeometry.stackPadding)
    }
}

/// Same blurred drops and threshold as the prototype's SVG liquid capsule.
struct TimelineLiquidRail: View {
    let layers: Int
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, _ in
            context.addFilter(.alphaThreshold(min: 9.0 / 22, color: Palette.active))
            context.addFilter(.blur(radius: 7))
            context.drawLayer { layer in
                for index in 0..<layers {
                    layer.fill(Path(ellipseIn: CGRect(x: 3, y: TimelineRowGeometry.layerHeight / 2 + CGFloat(index) * TimelineRowGeometry.layerHeight - 18, width: 36, height: 36)), with: .color(.black))
                }
                let tail = CGFloat(layers) * TimelineRowGeometry.layerHeight + 13
                layer.fill(Path(ellipseIn: CGRect(x: 8, y: tail - 13, width: 26, height: 26)), with: .color(.black))
                layer.fill(Path(CGRect(x: 12, y: 22, width: 18, height: tail - 22)), with: .color(.black))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
