import SwiftUI

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
