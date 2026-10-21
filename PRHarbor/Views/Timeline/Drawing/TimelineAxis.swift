import SwiftUI

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
                    Text(tick.text).font(.ui(Typography.footnote)).foregroundStyle(Palette.textTertiary).fixedSize()
                        .position(x: tick.age == Double(scale.days) ? Layout.axisLeadingLabelX : scale.position(age: tick.age) * geometry.size.width, y: Layout.axisLabelY)
                }
                Text("Today").font(.ui(Typography.caption, .semibold))
                    .foregroundStyle(Palette.inverseText).padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxxs)
                    .background(Palette.textPrimary, in: Capsule()).fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.bottom, Spacing.xxs)
                if let brush {
                    Button(action: clearBrush) {
                        HStack(spacing: Spacing.xs) { Text(brush.upperBound.isFinite ? "\(TimelinePolicy.duration(brush.lowerBound))–\(TimelinePolicy.duration(brush.upperBound))" : "\(TimelinePolicy.duration(brush.lowerBound))+"); Image(systemName: "xmark").font(.ui(Typography.micro)) }
                    }.buttonStyle(.primaryCompact).fixedSize()
                        .position(x: max(Layout.brushChipHalfWidth, min(geometry.size.width - Layout.brushChipHalfWidth, (scale.position(age: brush.lowerBound) + scale.position(age: brush.upperBound)) / 2 * geometry.size.width)), y: Layout.axisChipY)
                        .accessibilityLabel("Clear timeline selection")
                } else if let cursorAge {
                    Text(now.addingTimeInterval(-cursorAge * 86_400), format: .dateTime.month(.abbreviated).day())
                        .font(.ui(Typography.caption, .semibold)).padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xxxs)
                        .foregroundStyle(Palette.onAccent).background(Palette.accentFill, in: Capsule()).fixedSize()
                        .position(x: min(geometry.size.width - Layout.cursorChipHalfWidth, max(Layout.cursorChipHalfWidth, scale.position(age: cursorAge) * geometry.size.width)), y: Layout.axisChipY)
                }
            }
        }.frame(height: Layout.axisHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline, last \(scale.days) days. Today is on the right.")
    }
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
