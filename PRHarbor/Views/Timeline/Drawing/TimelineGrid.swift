import SwiftUI

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
                    context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(Palette.track.opacity(Opacity.weekendShade)))
                }
            }
            for tick in TimelineAxisLayout(scale: scale, now: now).gridAges where tick > 0 {
                let x = scale.position(age: tick) * size.width
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Palette.line), lineWidth: Stroke.hairline)
            }
            var today = Path(); today.move(to: CGPoint(x: size.width - Stroke.today / 2, y: 0)); today.addLine(to: CGPoint(x: size.width - Stroke.today / 2, y: size.height))
            context.stroke(today, with: .color(Palette.textPrimary.opacity(Opacity.todayLine)), lineWidth: Stroke.today)
            if let brush {
                let left = scale.position(age: brush.upperBound) * size.width
                let right = scale.position(age: brush.lowerBound) * size.width
                context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(Palette.accent.opacity(Opacity.brushFill)))
                for x in [left, right] {
                    var edge = Path(); edge.move(to: CGPoint(x: x, y: 0)); edge.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(edge, with: .color(Palette.accent.opacity(Opacity.brushEdge)), lineWidth: Stroke.hairline)
                }
            }
            if let cursorAge, brush == nil {
                let x = scale.position(age: cursorAge) * size.width
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Palette.accent), lineWidth: Stroke.hairline)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
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
