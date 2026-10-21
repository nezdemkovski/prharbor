import SwiftUI

struct TimelineTrack: View {
    let item: TimelineItem
    let scale: TimelineScale
    let now: Date
    var fixedWidth: CGFloat? = nil
    var body: some View {
        Group {
            if let fixedWidth { drawing(width: fixedWidth) } else { GeometryReader { drawing(width: $0.size.width) } }
        }
        .frame(height: Layout.trackHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(TimelinePolicy.duration(item.age)) old, \(item.standing), \(item.hasKnownQuietPeriod ? item.freshness.rawValue : "quiet time unknown")"
        )
        .accessibilityValue("\(item.events.count) events; \(item.events.last?.label ?? "opened")")
    }
    private func drawing(width: CGFloat) -> some View {
        let start = scale.position(age: item.age) * width
        let quietStart = item.hasKnownQuietPeriod ? max(start, scale.position(age: item.quietDays) * width) : width
        let tint = !item.isBlocked && item.hasKnownQuietPeriod ? item.freshness.fill : Palette.textTertiary
        let label = !item.isBlocked && item.hasKnownQuietPeriod ? item.freshness.label : Palette.textSecondary
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.l).fill(Palette.track)
            RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.line)
            Canvas(rendersAsynchronously: true) { context, size in
                let active = CGRect(
                    x: start, y: Layout.trackBarInset, width: max(0, quietStart - start), height: size.height - 2 * Layout.trackBarInset)
                context.fill(
                    UnevenRoundedRectangle(topLeadingRadius: Radius.s, bottomLeadingRadius: Radius.s).path(in: active),
                    with: .color(Palette.active))
                guard item.hasKnownQuietPeriod else { return }
                let quiet = CGRect(
                    x: quietStart, y: Layout.trackBarInset, width: max(2, size.width - quietStart),
                    height: size.height - 2 * Layout.trackBarInset)
                let leading = quietStart > start + 1 ? 0 : Radius.s
                let quietPath = UnevenRoundedRectangle(
                    topLeadingRadius: leading, bottomLeadingRadius: leading, bottomTrailingRadius: Radius.s, topTrailingRadius: Radius.s
                ).path(in: quiet)
                context.fill(quietPath, with: .color(tint.opacity(Opacity.tintFill)))
                context.stroke(quietPath, with: .color(tint.opacity(Opacity.tintStroke)), lineWidth: Stroke.hairline)
                context.clip(to: quietPath)
                var hatching = Path()
                for x in stride(from: quietStart - size.height, to: size.width + size.height, by: Layout.hatchSpacing) {
                    hatching.move(to: CGPoint(x: x, y: size.height))
                    hatching.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                context.stroke(hatching, with: .color(tint.opacity(Opacity.hatching)), lineWidth: Stroke.hatch)
            }
            .mask {
                if item.age > Double(scale.days) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: min(1, Layout.trackFadeWidth / max(1, width)))
                        ], startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
            .accessibilityHidden(true)
            ForEach(workEvents) { event in
                Rectangle().fill(Palette.textPrimary.opacity(Opacity.eventTick)).frame(
                    width: Size.eventTick.width, height: Size.eventTick.height
                )
                .position(x: scale.position(age: TimelinePolicy.days(since: event.date, now: now)) * width, y: Layout.trackHeight / 2)
                .help(event.label + " · " + event.date.formatted(date: .abbreviated, time: .shortened))
            }
            ForEach(clusters(width: width), id: \.id) { cluster in
                HStack(spacing: -Spacing.xs) {
                    ForEach(Array(cluster.events.prefix(3))) { event in
                        TimelineEventMark(event: event)
                    }
                    if cluster.events.count > 3 {
                        Text("+\(cluster.events.count - 3)").font(.ui(Typography.nano, .semibold))
                            .padding(Spacing.xxs).background(Palette.raised, in: Circle())
                    }
                }
                .position(x: max(Layout.trackEdgeInset, min(width - Layout.trackEdgeInset, cluster.position)), y: Layout.trackHeight / 2)
                .help(
                    cluster.events.map { $0.label + " · " + $0.date.formatted(date: .abbreviated, time: .omitted) }.joined(separator: "\n"))
            }
            if item.age > Double(scale.days) {
                Text("← \(TimelinePolicy.duration(item.age))").font(.ui(Typography.caption2, .semibold))
                    .foregroundStyle(Palette.textSecondary).padding(.leading, Spacing.s)
            }
            if let until = item.snoozedUntil {
                SwiftUI.Label(until.formatted(.dateTime.month(.abbreviated).day()), systemImage: "moon.zzz")
                    .font(.ui(Typography.caption2, .semibold)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, Spacing.s)
            } else if !item.hasKnownQuietPeriod {
                Text("quiet time unknown").font(.ui(Typography.caption2, .medium))
                    .foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, Spacing.s)
            } else if item.quietDays >= 2, width - quietStart > 32 {
                // A solid backing keeps the label's contrast independent of the hatching behind it.
                Text(TimelinePolicy.duration(item.quietDays)).font(.ui(Typography.footnote, .bold))
                    .foregroundStyle(label).padding(.horizontal, Spacing.xxs)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.xs))
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, Spacing.s)
            }
        }
        .frame(width: width, height: Layout.trackHeight)
    }
    private var workEvents: [TimelineEvent] {
        item.events.filter {
            ($0.kind == .commit || ($0.kind == .comment && $0.person?.login == item.pull.author?.login))
                && TimelinePolicy.days(since: $0.date, now: now) <= Double(scale.days)
        }
    }
    private struct Cluster {
        var id: Int
        var position: CGFloat
        var events: [TimelineEvent]
    }
    private func clusters(width: CGFloat) -> [Cluster] {
        var result: [Cluster] = []
        for event in item.events
        where event.kind != .opened && event.kind != .commit && !(event.kind == .comment && event.person?.login == item.pull.author?.login)
        {
            let age = TimelinePolicy.days(since: event.date, now: now)
            guard age <= Double(scale.days) else { continue }
            let x = scale.position(age: age) * width
            if let last = result.last, x - last.position < width * 0.032 {
                result[result.count - 1].events.append(event)
            } else {
                result.append(Cluster(id: event.id, position: x, events: [event]))
            }
        }
        return result
    }
}

struct TimelineEventMark: View {
    let event: TimelineEvent
    var body: some View {
        TimelineAvatar(person: event.person, size: Size.eventAvatar, miniature: true)
            .background(Circle().fill(Palette.raised).padding(-Spacing.xxs))
            .overlay(Circle().stroke(color, lineWidth: Stroke.eventRing).padding(-Stroke.eventRing / 2))
            .accessibilityLabel(event.label)
    }
    private var color: Color {
        switch event.kind {
        case .approved: Freshness.fresh.fill
        case .changes: Freshness.stale.fill
        case .requested: Palette.accent
        default: Palette.textSecondary.opacity(Opacity.deemphasized)
        }
    }
}
