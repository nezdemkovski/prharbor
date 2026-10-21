import AppKit
import SwiftUI

/// AppKit owns scrolling; only the viewport and a small prefetch margin have
/// SwiftUI hosts. The full document keeps stable geometry and scrollbar size.
struct TimelineNativeScrollView<Content: View>: NSViewRepresentable {
    let height: CGFloat
    let rowIDs: [String]
    let ranges: [String: Range<CGFloat>]
    let selection: String?
    let interaction: TimelineInteraction
    let content: (String) -> Content
    var placeholder: (String) -> TimelineRowPlaceholder = { _ in TimelineRowPlaceholder(title: "", subtitle: "") }
    var activate: (String) -> Void = { _ in }
    /// A click below the last row or between rows.
    var clickEmptySpace: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    func makeNSView(context: Context) -> TimelineAppKitScrollView {
        let scroll = TimelineAppKitScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.interaction = interaction
        scroll.documentView = context.coordinator.document
        return scroll
    }

    static func dismantleNSView(_ scroll: TimelineAppKitScrollView, coordinator: Coordinator) {
        coordinator.document.stopLoading()
        scroll.documentView = nil
        scroll.interaction?.isScrolling = false
    }

    func updateNSView(_ scroll: TimelineAppKitScrollView, context: Context) {
        let coordinator = context.coordinator
        let top = scroll.contentView.bounds.minY
        let anchor = coordinator.rowIDs.first { (coordinator.ranges[$0]?.upperBound ?? 0) > top }
        let offset = anchor.flatMap { coordinator.ranges[$0] }.map { top - $0.lowerBound } ?? 0
        let changedSelection = coordinator.selection != selection
        coordinator.selection = selection
        coordinator.document.configure(
            height: height, rowIDs: rowIDs, ranges: ranges, content: content,
            placeholder: placeholder, activate: activate, clickEmptySpace: clickEmptySpace,
            appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        coordinator.rowIDs = rowIDs
        coordinator.ranges = ranges
        // Replace the visible content in this update, before AppKit can draw a frame of
        // placeholders. The row area has a fixed height, so the viewport is already final.
        coordinator.positionViewport(scroll, anchor: anchor, offset: offset, top: top, changedSelection: changedSelection)
    }

    @MainActor final class Coordinator {
        let document: TimelineVirtualDocumentView<Content>
        var rowIDs: [String] = []
        var ranges: [String: Range<CGFloat>] = [:]
        var selection: String?
        init(content: @escaping (String) -> Content) { document = TimelineVirtualDocumentView(content: content) }

        func positionViewport(
            _ scroll: TimelineAppKitScrollView, anchor: String?, offset: CGFloat,
            top: CGFloat, changedSelection: Bool
        ) {
            let viewport = scroll.contentView.bounds
            var y = anchor.flatMap { ranges[$0] }.map { $0.lowerBound + offset } ?? top
            if changedSelection, let selection, let range = ranges[selection] {
                if range.lowerBound < y {
                    y = range.lowerBound
                } else if range.upperBound > y + viewport.height {
                    y = range.upperBound - viewport.height
                }
            }
            let maximum = max(0, document.frame.height - viewport.height)
            y = min(maximum, max(0, y))
            if abs(viewport.minY - y) > 0.5 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            document.refreshViewport(scroll.contentView.bounds)
        }
    }
}
