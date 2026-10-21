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
                // Only the label column expands the stack; its bars belong to the timeline pointer.
                HStack(spacing: 0) {
                    Button(action: toggle) {
                        SwiftUI.Label("Stack · \(items.count) layers", systemImage: "square.3.layers.3d")
                            .font(.ui(Typography.callout, .medium)).frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                            .frame(maxHeight: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    VStack(spacing: TimelineRowGeometry.collapsedBarSpacing) {
                        ForEach(items) { item in
                            GeometryReader { geometry in
                                let start = scale.position(age: item.age) * geometry.size.width
                                Capsule().fill(
                                    (item.hasKnownQuietPeriod ? item.freshness.fill : Palette.textTertiary).opacity(Opacity.quietBar)
                                ).frame(width: max(2, geometry.size.width - start)).offset(x: start)
                            }.frame(height: TimelineRowGeometry.collapsedBarHeight)
                        }
                    }
                }
                .frame(height: TimelineRowGeometry.collapsedBodyHeight(layers: items.count))
                .padding(TimelineRowGeometry.collapsedContentPadding)
            } else {
                ForEach(items) { item in
                    TimelineRow(item: item, scale: scale, now: now, selected: selection == item.id, layer: true) { select(item.id) }.id(
                        item.id)
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
                                Text(
                                    "· "
                                        + (mergedStyle == .count
                                            ? "\(merged.count) merged" : merged.map { "#\($0.number)" }.joined(separator: " "))
                                )
                                .font(.ui(Typography.footnote)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                                .help(merged.map { "#\($0.number) \($0.title)" }.joined(separator: "\n"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(Palette.textSecondary).frame(height: Layout.stackFooterHeight)
                    .frame(width: TimelineMetrics.labelWidth, height: TimelineRowGeometry.stackFooterHeight, alignment: .topLeading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(isCollapsed ? "Expand stack" : "Collapse stack")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(alignment: .topLeading) {
            if !isCollapsed {
                TimelineLiquidRail(layers: items.count).frame(
                    width: Layout.stackRailWidth,
                    height: CGFloat(items.count) * TimelineRowGeometry.layerHeight + TimelineRowGeometry.stackFooterHeight
                ).offset(x: Layout.stackRailOffset)
            }
        }
        .padding(.vertical, TimelineRowGeometry.stackPadding)
    }
}

/// Same blurred drops and threshold as the prototype's SVG liquid capsule.
struct TimelineLiquidRail: View {
    let layers: Int
    // A drop behind each layer's avatar, a smaller one at the base, and a stem joining them;
    // blurring and thresholding merges them into one capsule.
    private static let drop = CGRect(x: 3, y: 0, width: 36, height: 36)
    private static let base = CGRect(x: 8, y: 0, width: 26, height: 26)
    private static let stem = CGRect(x: 12, y: 22, width: 18, height: 0)
    private static let blur: CGFloat = 7
    private static let threshold = 9.0 / 22

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, _ in
            context.addFilter(.alphaThreshold(min: Self.threshold, color: Palette.active))
            context.addFilter(.blur(radius: Self.blur))
            context.drawLayer { layer in
                let layerHeight = TimelineRowGeometry.layerHeight
                for index in 0..<layers {
                    let center = layerHeight / 2 + CGFloat(index) * layerHeight
                    layer.fill(Path(ellipseIn: Self.drop.offsetBy(dx: 0, dy: center - Self.drop.height / 2)), with: .color(.black))
                }
                let baseCenter = CGFloat(layers) * layerHeight + Self.base.height / 2
                layer.fill(Path(ellipseIn: Self.base.offsetBy(dx: 0, dy: baseCenter - Self.base.height / 2)), with: .color(.black))
                var stem = Self.stem
                stem.size.height = baseCenter - stem.minY
                layer.fill(Path(stem), with: .color(.black))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
