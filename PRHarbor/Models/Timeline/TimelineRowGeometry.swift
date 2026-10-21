import Foundation

/// One sizing contract for SwiftUI rows and the virtual AppKit document.
nonisolated enum TimelineRowGeometry {
    static let repositoryHeight: CGFloat = 40
    static let pullHeight: CGFloat = 50
    static let layerHeight: CGFloat = 44
    static let stackPadding: CGFloat = 4
    static let stackFooterHeight: CGFloat = 32
    static let collapsedBarHeight: CGFloat = 4
    static let collapsedBarSpacing: CGFloat = 2
    static let collapsedLabelHeight: CGFloat = 14
    static let collapsedContentPadding: CGFloat = 8
    static let documentBottomPadding: CGFloat = 4

    static func collapsedBarsHeight(layers: Int) -> CGFloat {
        CGFloat(max(0, layers)) * collapsedBarHeight + CGFloat(max(0, layers - 1)) * collapsedBarSpacing
    }
    static func collapsedContentHeight(layers: Int) -> CGFloat {
        collapsedBodyHeight(layers: layers) + collapsedContentPadding * 2
    }
    static func collapsedBodyHeight(layers: Int) -> CGFloat {
        max(collapsedLabelHeight, collapsedBarsHeight(layers: layers))
    }
    static func stackHeight(layers: Int, collapsed: Bool) -> CGFloat {
        (collapsed ? collapsedContentHeight(layers: layers) : CGFloat(layers) * layerHeight)
            + stackFooterHeight + stackPadding * 2
    }
    static func layerRange(index: Int, origin: CGFloat) -> Range<CGFloat> {
        let start = origin + stackPadding + CGFloat(index) * layerHeight
        return start..<(start + layerHeight)
    }
}
