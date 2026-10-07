import SwiftUI
import Observation

private enum TimelineFreshnessColors {
    static let fresh = TimelineStyle.color(0x22b25b)
    static let aging = TimelineStyle.color(0xd4a106)
    static let stale = TimelineStyle.color(0xf07a1a)
    static let rotting = TimelineStyle.color(0xe5484d)
}

extension Freshness {
    var color: Color {
        switch self {
        case .fresh: TimelineFreshnessColors.fresh
        case .aging: TimelineFreshnessColors.aging
        case .stale: TimelineFreshnessColors.stale
        case .rotting: TimelineFreshnessColors.rotting
        }
    }
}

enum TimelineMetrics {
    static let panelWidth: CGFloat = 780
    static let labelWidth: CGFloat = 270
    static let inset: CGFloat = 18
    static let trackWidth = panelWidth - 2 * inset - labelWidth
}

/// Axis labels and grid lines follow the prototype's log and Monday-aligned scales.
struct TimelineAxisLayout {
    let scale: TimelineScale
    let now: Date
    var gridAges: [Double] {
        if scale.isLogarithmic { return [1, 3, 7, 14, 30, 60, 90].filter { $0 < Double(scale.days) } }
        let step = scale.days <= 14 ? 1 : scale.days <= 30 ? 7 : 14
        let offset = scale.days <= 14 ? 0 : (Calendar.current.component(.weekday, from: now) + 5) % 7
        return stride(from: offset, through: scale.days, by: step).map(Double.init)
    }
    var labels: [(age: Double, text: String)] {
        if scale.isLogarithmic {
            var previous: Double = 1
            var result: [(Double, String)] = [(Double(scale.days), "6mo")]
            for (age, text) in [(1.0, "1d"), (3, "3d"), (7, "1w"), (14, "2w"), (30, "1mo"), (60, "2mo"), (90, "3mo")] {
                let x = scale.position(age: age)
                if 1 - x > 0.13 && previous - x > 0.055 && x > 0.03 {
                    result.append((age, text)); previous = x
                }
            }
            return result
        }
        return gridAges.enumerated().compactMap { index, age in
            let x = scale.position(age: age)
            guard (scale.days > 14 || index % 2 == 0), 1 - x > 0.13, x > 0.03 else { return nil }
            return (age, now.addingTimeInterval(-age * 86_400).formatted(.dateTime.month(.abbreviated).day()))
        }
    }
}

struct TimelineAxis: View {
    let scale: TimelineScale
    let now: Date
    var cursorAge: Double?
    var brush: ClosedRange<Double>?
    var clearBrush: () -> Void = {}
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: TimelineMetrics.labelWidth)
            GeometryReader { geometry in
                ForEach(TimelineAxisLayout(scale: scale, now: now).labels, id: \.age) { tick in
                    Text(tick.text).font(.system(size: 11)).foregroundStyle(TimelineStyle.faint).fixedSize()
                        .position(x: tick.age == Double(scale.days) ? 12 : scale.position(age: tick.age) * geometry.size.width, y: 16)
                }
                Text("Today").font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(TimelineStyle.panel).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(TimelineStyle.text, in: Capsule()).fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.bottom, 3)
                if let brush {
                    Button(action: clearBrush) {
                        HStack(spacing: 5) { Text(brush.upperBound.isFinite ? "\(TimelinePolicy.duration(brush.lowerBound))–\(TimelinePolicy.duration(brush.upperBound))" : "\(TimelinePolicy.duration(brush.lowerBound))+"); Image(systemName: "xmark").font(.system(size: 9)) }
                            .font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                            .foregroundStyle(.white).background(TimelineStyle.accent, in: Capsule())
                    }.buttonStyle(.plain).fixedSize()
                        .position(x: max(45, min(geometry.size.width - 45, (scale.position(age: brush.lowerBound) + scale.position(age: brush.upperBound)) / 2 * geometry.size.width)), y: 18)
                        .accessibilityLabel("Clear timeline selection")
                } else if let cursorAge {
                    Text(now.addingTimeInterval(-cursorAge * 86_400), format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                        .foregroundStyle(.white).background(TimelineStyle.accent, in: Capsule()).fixedSize()
                        .position(x: min(geometry.size.width - 35, max(35, scale.position(age: cursorAge) * geometry.size.width)), y: 18)
                }
            }
        }.frame(height: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline, last \(scale.days) days. Today is on the right.")
    }
}

struct TimelineGrid: View {
    let scale: TimelineScale
    let now: Date
    var cursorAge: Double?
    var brush: ClosedRange<Double>?
    var body: some View {
        Canvas { context, size in
            if scale.days <= 14 {
                for day in 0...scale.days where Calendar.current.component(.weekday, from: now.addingTimeInterval(-Double(day) * 86_400)) == 7 {
                    let left = scale.position(age: Double(day) + 0.44) * size.width
                    let right = scale.position(age: Double(day) - 1.56) * size.width
                    context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(TimelineStyle.track.opacity(0.7)))
                }
            }
            for tick in TimelineAxisLayout(scale: scale, now: now).gridAges where tick > 0 {
                let x = scale.position(age: tick) * size.width
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(TimelineStyle.line), lineWidth: 1)
            }
            var today = Path(); today.move(to: CGPoint(x: size.width - 0.75, y: 0)); today.addLine(to: CGPoint(x: size.width - 0.75, y: size.height))
            context.stroke(today, with: .color(TimelineStyle.text.opacity(0.75)), lineWidth: 2)
            if let brush {
                let left = scale.position(age: brush.upperBound) * size.width
                let right = scale.position(age: brush.lowerBound) * size.width
                context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(TimelineStyle.accent.opacity(0.09)))
                for x in [left, right] {
                    var edge = Path(); edge.move(to: CGPoint(x: x, y: 0)); edge.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(edge, with: .color(TimelineStyle.accent.opacity(0.55)), lineWidth: 1)
                }
            }
            if let cursorAge, brush == nil {
                let x = scale.position(age: cursorAge) * size.width
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(TimelineStyle.accent), lineWidth: 1)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TimelineTrack: View {
    let item: TimelineItem
    let scale: TimelineScale
    let now: Date
    var fixedWidth: CGFloat? = nil
    var body: some View {
        Group {
            if let fixedWidth { drawing(width: fixedWidth) }
            else { GeometryReader { drawing(width: $0.size.width) } }
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(TimelinePolicy.duration(item.age)) old, \(item.standing), \(item.hasKnownQuietPeriod ? item.freshness.rawValue : "quiet time unknown")")
        .accessibilityValue("\(item.events.count) events; \(item.events.last?.label ?? "opened")")
    }
    private func drawing(width: CGFloat) -> some View {
        let start = scale.position(age: item.age) * width
        let quietStart = item.hasKnownQuietPeriod ? max(start, scale.position(age: item.quietDays) * width) : width
        let color = !item.isBlocked && item.hasKnownQuietPeriod ? item.freshness.color : TimelineStyle.faint
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(TimelineStyle.track)
            RoundedRectangle(cornerRadius: 10).strokeBorder(TimelineStyle.line)
            Canvas(rendersAsynchronously: true) { context, size in
                let active = CGRect(x: start, y: 5, width: max(0, quietStart - start), height: size.height - 10)
                context.fill(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7).path(in: active), with: .color(TimelineStyle.active))
                guard item.hasKnownQuietPeriod else { return }
                let quiet = CGRect(x: quietStart, y: 5, width: max(2, size.width - quietStart), height: size.height - 10)
                let quietPath = UnevenRoundedRectangle(topLeadingRadius: quietStart > start + 1 ? 0 : 7, bottomLeadingRadius: quietStart > start + 1 ? 0 : 7, bottomTrailingRadius: 7, topTrailingRadius: 7).path(in: quiet)
                context.fill(quietPath, with: .color(color.opacity(0.14)))
                context.stroke(quietPath, with: .color(color.opacity(0.45)), lineWidth: 1)
                context.clip(to: quietPath)
                var hatching = Path()
                for x in stride(from: quietStart - size.height, to: size.width + size.height, by: 6 * sqrt(2.0)) {
                    hatching.move(to: CGPoint(x: x, y: size.height))
                    hatching.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                context.stroke(hatching, with: .color(color.opacity(0.42)), lineWidth: 2)
            }
            .mask {
                if item.age > Double(scale.days) {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: min(1, 24 / max(1, width)))], startPoint: .leading, endPoint: .trailing)
                } else { Rectangle() }
            }
            .accessibilityHidden(true)
            ForEach(workEvents) { event in
                Rectangle().fill(TimelineStyle.text.opacity(0.38)).frame(width: 1.5, height: 12)
                    .position(x: scale.position(age: TimelinePolicy.days(since: event.date, now: now)) * width, y: 17)
                    .help(event.label + " · " + event.date.formatted(date: .abbreviated, time: .shortened))
            }
            ForEach(clusters(width: width), id: \.id) { cluster in
                HStack(spacing: -5) {
                    ForEach(Array(cluster.events.prefix(3))) { event in
                        TimelineEventMark(event: event)
                    }
                    if cluster.events.count > 3 {
                        Text("+\(cluster.events.count - 3)").font(.system(size: 8, weight: .semibold))
                            .padding(3).background(TimelineStyle.panel, in: Circle())
                    }
                }
                .position(x: max(12, min(width - 12, cluster.position)), y: 17)
                .help(cluster.events.map { $0.label + " · " + $0.date.formatted(date: .abbreviated, time: .omitted) }.joined(separator: "\n"))
            }
            if item.age > Double(scale.days) {
                Text("← \(TimelinePolicy.duration(item.age))").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TimelineStyle.muted).padding(.leading, 6)
            }
            if let until = item.snoozedUntil {
                SwiftUI.Label(until.formatted(.dateTime.month(.abbreviated).day()), systemImage: "moon.zzz")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(TimelineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 6)
            } else if !item.hasKnownQuietPeriod {
                Text("quiet time unknown").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TimelineStyle.muted).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 6)
            } else if item.quietDays >= 2, width - quietStart > 32 {
                Text(TimelinePolicy.duration(item.quietDays)).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 6)
            }
        }
        .frame(width: width, height: 34)
    }
    private var workEvents: [TimelineEvent] {
        item.events.filter { ($0.kind == .commit || ($0.kind == .comment && $0.person?.login == item.pull.author?.login)) && TimelinePolicy.days(since: $0.date, now: now) <= Double(scale.days) }
    }
    private struct Cluster {
        var id: Int
        var position: CGFloat
        var events: [TimelineEvent]
    }
    private func clusters(width: CGFloat) -> [Cluster] {
        var result: [Cluster] = []
        for event in item.events where event.kind != .opened && event.kind != .commit && !(event.kind == .comment && event.person?.login == item.pull.author?.login) {
            let age = TimelinePolicy.days(since: event.date, now: now)
            guard age <= Double(scale.days) else { continue }
            let x = scale.position(age: age) * width
            if let last = result.last, x - last.position < width * 0.032 {
                result[result.count - 1].events.append(event)
            } else { result.append(Cluster(id: event.id, position: x, events: [event])) }
        }
        return result
    }
}

struct TimelineEventMark: View {
    let event: TimelineEvent
    var body: some View {
        TimelineAvatar(person: event.person, size: 16, miniature: true)
            .background(Circle().fill(TimelineStyle.panel).padding(-3))
            .overlay(Circle().stroke(color, lineWidth: 1.5).padding(-0.75))
            .accessibilityLabel(event.label)
    }
    private var color: Color {
        switch event.kind {
        case .approved: Freshness.fresh.color
        case .changes: Freshness.stale.color
        case .requested: TimelineStyle.accent
        default: TimelineStyle.muted.opacity(0.7)
        }
    }
}

struct TimelineAvatar: View {
    let person: User?
    let size: CGFloat
    var miniature = false
    var body: some View {
        Group {
            if let url = person?.avatarUrl { AsyncAvatarView(url: url) }
            else {
                let login = person?.login ?? "ghost"
                ZStack {
                    Circle().fill(miniature ? AnyShapeStyle(TimelineStyle.track) : AnyShapeStyle(gradient(login)))
                    Text(String((login == "yuri" ? "You" : login).prefix(1)).uppercased())
                        .font(.system(size: miniature ? 8.5 : 12, weight: .semibold))
                        .foregroundStyle(miniature ? TimelineStyle.muted : .white)
                }
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
    private func gradient(_ login: String) -> LinearGradient {
        let mockColors: [String: (Int, Int)] = ["yuri": (0xf59e0b, 0xef4444), "anna": (0x8b5cf6, 0x6366f1), "marek": (0x06b6d4, 0x3b82f6), "tomas": (0x10b981, 0x059669), "lena": (0xec4899, 0xf43f5e)]
        if let colors = mockColors[login] {
            return LinearGradient(colors: [TimelineStyle.color(colors.0), TimelineStyle.color(colors.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let hue = login.utf16.reduce(0) { ($0 * 31 + Int($1)) % 360 }
        return LinearGradient(colors: [Color(hue: Double(hue) / 360, saturation: 0.7, brightness: 0.9), Color(hue: Double((hue + 40) % 360) / 360, saturation: 0.7, brightness: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

nonisolated struct PullRequestGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for y in [3.25, 12.75] {
            p.addEllipse(in: CGRect(x: 1.5, y: y - 2.25, width: 4.5, height: 4.5))
            p.addEllipse(in: CGRect(x: 3, y: y - 0.75, width: 1.5, height: 1.5))
        }
        p.addRect(CGRect(x: 3, y: 5.372, width: 1.5, height: 5.256))
        p.addEllipse(in: CGRect(x: 10.5, y: 10.5, width: 4.5, height: 4.5))
        p.addEllipse(in: CGRect(x: 12, y: 12, width: 1.5, height: 1.5))
        p.move(to: CGPoint(x: 7.177, y: 3.073)); p.addLine(to: CGPoint(x: 9.573, y: 0.677))
        p.addQuadCurve(to: CGPoint(x: 10, y: 0.854), control: CGPoint(x: 10, y: 0.5))
        p.addLine(to: CGPoint(x: 10, y: 2.5)); p.addLine(to: CGPoint(x: 11, y: 2.5))
        p.addQuadCurve(to: CGPoint(x: 13.5, y: 5), control: CGPoint(x: 13.5, y: 2.5))
        p.addLine(to: CGPoint(x: 13.5, y: 10.628)); p.addLine(to: CGPoint(x: 12, y: 10.628)); p.addLine(to: CGPoint(x: 12, y: 5))
        p.addQuadCurve(to: CGPoint(x: 11, y: 4), control: CGPoint(x: 12, y: 4)); p.addLine(to: CGPoint(x: 10, y: 4))
        p.addLine(to: CGPoint(x: 10, y: 5.646)); p.addQuadCurve(to: CGPoint(x: 9.573, y: 5.823), control: CGPoint(x: 10, y: 6))
        p.addLine(to: CGPoint(x: 7.177, y: 3.427)); p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16).translatedBy(x: rect.minX, y: rect.minY))
    }
}



/// Only axis/grid depend on pointer movement; rows and data preparation do not.
@Observable
final class TimelineInteraction {
    var cursorAge: Double?
    var dragging: ClosedRange<Double>?
    @ObservationIgnored var brushing = false
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored var scale = TimelineScale(days: 182)
    private let width = TimelineMetrics.panelWidth - 2 * TimelineMetrics.inset - TimelineMetrics.labelWidth
    private let trackOrigin = TimelineMetrics.inset + TimelineMetrics.labelWidth
    func hover(at x: CGFloat) {
        // Gestures are attached after padding, so their coordinates include the inset.
        let position = x - trackOrigin
        let value = position >= 0 && position <= width ? scale.age(at: position / width) : nil
        // A subpixel mouse move must not invalidate an identical displayed position.
        if value != cursorAge { cursorAge = value }
    }
    func drag(from startX: CGFloat, to endX: CGFloat, scale: TimelineScale) {
        let start = startX - trackOrigin
        guard start >= 0, start <= width else { return }
        brushing = true
        let first = scale.age(at: start / width)
        let second = scale.age(at: (endX - trackOrigin) / width)
        let lower = scale.snappedAge(min(first, second)), upper = scale.snappedAge(max(first, second))
        let value: ClosedRange<Double>? = lower == upper ? nil : lower...(upper >= Double(scale.days) ? .infinity : upper)
        if dragging != value { dragging = value }
    }
    func endDrag() { dragging = nil; brushing = false }
}

struct TimelineInteractiveAxis: View {
    let scale: TimelineScale
    let now: Date
    let interaction: TimelineInteraction
    let brush: ClosedRange<Double>?
    let clearBrush: () -> Void
    var body: some View {
        TimelineAxis(scale: scale, now: now, cursorAge: interaction.cursorAge,
                     brush: interaction.dragging ?? brush, clearBrush: clearBrush)
    }
}

struct TimelineInteractiveGrid: View {
    let scale: TimelineScale
    let now: Date
    let interaction: TimelineInteraction
    let brush: ClosedRange<Double>?
    var body: some View {
        TimelineGrid(scale: scale, now: now, cursorAge: interaction.cursorAge, brush: interaction.dragging ?? brush)
    }
}
