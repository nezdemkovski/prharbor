import SwiftUI
import Defaults

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
                                    .frame(minWidth: Size.positionBadge).frame(height: Size.positionBadge).background(Palette.panel, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Palette.strong)).offset(x: 5, y: 4)
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
                .fill(selected ? Palette.accentSoft.opacity(Opacity.rowSelected) : hovering ? Palette.hover.opacity(Opacity.rowHover) : .clear)
                .padding(.vertical, Spacing.xxxs).padding(.horizontal, -Spacing.m)
        }
        .onHover { if hovering != $0 { hovering = $0 } }
    }
}

struct TimelineRepositoryHeader: View {
    let name: String
    let items: [TimelineItem]
    let scale: TimelineScale
    let collapsed: Bool
    var showOwner = false
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.ui(Typography.micro, .semibold)).frame(width: Size.disclosure)
                    if name == "Bots" { Image(systemName: "gearshape.2") }
                    HStack(spacing: 0) {
                        if showOwner, name.contains("/"), let owner = name.split(separator: "/").first { Text(String(owner) + "/").fontWeight(.medium).foregroundStyle(Palette.textTertiary) }
                        Text(name == "Bots" ? name : String(name.split(separator: "/").last ?? ""))
                    }.lineLimit(1)
                    Text("\(items.count)").foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .font(.ui(Typography.callout, .semibold)).foregroundStyle(Palette.textSecondary)
                .frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                GeometryReader { geometry in
                    if collapsed {
                        ForEach(items.filter(\.hasKnownQuietPeriod)) { item in
                            Circle().fill(item.freshness.fill).frame(width: Size.dot, height: Size.dot)
                                .position(x: max(4, min(geometry.size.width - 4, scale.position(age: item.quietDays) * geometry.size.width)), y: 17)
                        }
                    }
                }
            }
            .frame(height: TimelineRowGeometry.repositoryHeight - 6).padding(.top, Spacing.s).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(items.count) pull requests, \(collapsed ? "collapsed" : "expanded")")
    }
}

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
                        .background(Palette.panel, in: Circle()).overlay(Circle().strokeBorder(Palette.strong))
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

struct TimelineSummary: View {
    let items: [TimelineItem]
    @Binding var zone: Freshness?
    var body: some View {
        HStack(spacing: Spacing.xxl) {
            HStack(spacing: Spacing.xxxs) {
                ForEach(Freshness.allCases) { freshness in
                    let count = items.filter { $0.snoozedUntil == nil && $0.hasKnownQuietPeriod && $0.freshness == freshness }.count
                    Button {
                        zone = zone == freshness ? nil : freshness
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Circle().fill(freshness.fill).frame(width: Size.dot, height: Size.dot)
                            Text(freshness.rawValue)
                            Text("\(count)").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
                        }
                        .font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xxs).frame(height: Size.chip)
                        .background(zone == freshness ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
                        .overlay { if zone == freshness { RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.strong) } }
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0 && zone != freshness).opacity(count == 0 ? 0.45 : 1)
                    .accessibilityAddTraits(zone == freshness ? [.isSelected] : [])
                }
            }
            .padding(Spacing.xxs).background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line))
            let people = Set(items.filter { !$0.isMine && !$0.isBot && $0.reviewRequested && $0.snoozedUntil == nil }.compactMap { $0.pull.author?.login }).count
            if people > 0 {
                Text("blocking **\(people)** \(people == 1 ? "person" : "people")").font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
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
