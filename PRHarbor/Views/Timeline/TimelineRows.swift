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
                HStack(spacing: 10) {
                    TimelineAvatar(person: item.pull.author, size: 30)
                        .accessibilityHidden(true)
                        .overlay(alignment: .bottomTrailing) {
                            if layer, let position = item.pull.stackEntry?.position {
                                Text("\(position)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(TimelineStyle.muted)
                                    .frame(minWidth: 16).frame(height: 16).background(TimelineStyle.panel, in: Capsule())
                                    .overlay(Capsule().strokeBorder(TimelineStyle.strong)).offset(x: 5, y: 4)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(verbatim: "#\(item.pull.number)")
                            if let detail = item.isMine ? item.ticket : item.pull.author?.login { Text("·"); Text(detail).lineLimit(1) }
                            if item.pull.isDraft { Text("· draft") }
                            if item.snoozedUntil != nil { Image(systemName: "moon.zzz") }
                        }
                        .font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 14)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? TimelineStyle.accentSoft.opacity(0.55) : hovering ? TimelineStyle.hover.opacity(0.7) : .clear)
                .padding(.vertical, 2).padding(.horizontal, -8)
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
                HStack(spacing: 5) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).frame(width: 12)
                    if name == "Bots" { Image(systemName: "gearshape.2") }
                    HStack(spacing: 0) {
                        if showOwner, name.contains("/"), let owner = name.split(separator: "/").first { Text(String(owner) + "/").fontWeight(.medium).foregroundStyle(TimelineStyle.faint) }
                        Text(name == "Bots" ? name : String(name.split(separator: "/").last ?? ""))
                    }.lineLimit(1)
                    Text("\(items.count)").foregroundStyle(TimelineStyle.faint)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(TimelineStyle.muted)
                .frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                GeometryReader { geometry in
                    if collapsed {
                        ForEach(items.filter(\.hasKnownQuietPeriod)) { item in
                            Circle().fill(item.freshness.color).frame(width: 7, height: 7)
                                .position(x: max(4, min(geometry.size.width - 4, scale.position(age: item.quietDays) * geometry.size.width)), y: 17)
                        }
                    }
                }
            }
            .frame(height: TimelineRowGeometry.repositoryHeight - 6).padding(.top, 6).contentShape(Rectangle())
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
                            .font(.system(size: 12, weight: .medium)).frame(width: TimelineMetrics.labelWidth, alignment: .leading)
                        VStack(spacing: TimelineRowGeometry.collapsedBarSpacing) {
                            ForEach(items) { item in
                                GeometryReader { geometry in
                                    let start = scale.position(age: item.age) * geometry.size.width
                                    Capsule().fill((item.hasKnownQuietPeriod ? item.freshness.color : TimelineStyle.faint).opacity(0.6)).frame(width: max(2, geometry.size.width - start)).offset(x: start)
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
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).frame(width: 22, height: 22)
                        .background(TimelineStyle.panel, in: Circle()).overlay(Circle().strokeBorder(TimelineStyle.strong))
                        .padding(.horizontal, 4)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(group.stack?.baseRefName ?? "base").font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        if mergedStyle != 2, let entries = group.stack?.entries?.nodes {
                            let merged = entries.compactMap(\.pullRequest).filter { $0.state == "MERGED" }
                            if !merged.isEmpty {
                                Text("· " + (mergedStyle == 0 ? "\(merged.count) merged" : merged.map { "#\($0.number)" }.joined(separator: " ")))
                                    .font(.system(size: 11)).foregroundStyle(TimelineStyle.faint).lineLimit(1)
                                    .help(merged.map { "#\($0.number) \($0.title)" }.joined(separator: "\n"))
                            }
                        }
                    }
                    Spacer()
                }.foregroundStyle(TimelineStyle.muted).frame(height: 26)
                    .frame(height: TimelineRowGeometry.stackFooterHeight, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(.plain).help(isCollapsed ? "Expand stack" : "Collapse stack")
        }
        .background(alignment: .topLeading) {
            if !isCollapsed {
                TimelineLiquidRail(layers: items.count).frame(width: 42, height: CGFloat(items.count) * TimelineRowGeometry.layerHeight + TimelineRowGeometry.stackFooterHeight).offset(x: -6)
            }
        }
        .padding(.vertical, TimelineRowGeometry.stackPadding)
    }
}

struct TimelineSummary: View {
    let items: [TimelineItem]
    @Binding var zone: Freshness?
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(Freshness.allCases) { freshness in
                    let count = items.filter { $0.snoozedUntil == nil && $0.hasKnownQuietPeriod && $0.freshness == freshness }.count
                    Button {
                        zone = zone == freshness ? nil : freshness
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(freshness.color).frame(width: 7, height: 7)
                            Text(freshness.rawValue)
                            Text("\(count)").fontWeight(.semibold).foregroundStyle(TimelineStyle.text)
                        }
                        .font(.system(size: 12)).foregroundStyle(TimelineStyle.muted)
                        .padding(.horizontal, 9).padding(.vertical, 3).frame(height: 22)
                        .background(zone == freshness ? TimelineStyle.panel : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .overlay { if zone == freshness { RoundedRectangle(cornerRadius: 7).strokeBorder(TimelineStyle.strong) } }
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0 && zone != freshness).opacity(count == 0 ? 0.45 : 1)
                    .accessibilityAddTraits(zone == freshness ? [.isSelected] : [])
                }
            }
            .padding(3).background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TimelineStyle.line))
            let people = Set(items.filter { !$0.isMine && !$0.isBot && $0.reviewRequested && $0.snoozedUntil == nil }.compactMap { $0.pull.author?.login }).count
            if people > 0 {
                Text("blocking **\(people)** \(people == 1 ? "person" : "people")").font(.system(size: 12)).foregroundStyle(TimelineStyle.muted)
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
            context.addFilter(.alphaThreshold(min: 9.0 / 22, color: TimelineStyle.active))
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
