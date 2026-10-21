import SwiftUI

struct TimelineHatching: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Radius.xs)
            context.fill(rect, with: .color(color.opacity(Opacity.tintFill)))
            context.stroke(rect, with: .color(color.opacity(Opacity.tintStroke)), lineWidth: Stroke.hairline)
            context.clip(to: rect)
            for x in stride(from: -size.height, to: size.width + size.height, by: 6 * sqrt(2.0)) {
                var line = Path(); line.move(to: CGPoint(x: x, y: size.height)); line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(color.opacity(Opacity.hatching)), lineWidth: Stroke.hatch)
            }
        }.accessibilityHidden(true)
    }
}
