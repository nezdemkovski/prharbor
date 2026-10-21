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
        coordinator.generation += 1
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
        coordinator.document.configure(height: height, rowIDs: rowIDs, ranges: ranges, content: content,
            placeholder: placeholder, activate: activate, appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        coordinator.rowIDs = rowIDs
        coordinator.ranges = ranges
        coordinator.generation += 1
        let generation = coordinator.generation
        // Replace the visible content in this update, before AppKit can draw a
        // frame of placeholders. Recheck after SwiftUI settles the panel size.
        coordinator.positionViewport(scroll, anchor: anchor, offset: offset, top: top, changedSelection: changedSelection)
        DispatchQueue.main.async { [weak scroll, weak coordinator] in
            guard let scroll, let coordinator, coordinator.generation == generation else { return }
            coordinator.positionViewport(scroll, anchor: anchor, offset: offset, top: top, changedSelection: changedSelection)
        }
    }

    @MainActor final class Coordinator {
        let document: TimelineVirtualDocumentView<Content>
        var rowIDs: [String] = []
        var ranges: [String: Range<CGFloat>] = [:]
        var selection: String?
        var generation = 0
        init(content: @escaping (String) -> Content) { document = TimelineVirtualDocumentView(content: content) }

        func positionViewport(_ scroll: TimelineAppKitScrollView, anchor: String?, offset: CGFloat,
                              top: CGFloat, changedSelection: Bool) {
            let viewport = scroll.contentView.bounds
            var y = anchor.flatMap { ranges[$0] }.map { $0.lowerBound + offset } ?? top
            if changedSelection, let selection, let range = ranges[selection] {
                if range.lowerBound < y { y = range.lowerBound }
                else if range.upperBound > y + viewport.height { y = range.upperBound - viewport.height }
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

nonisolated enum TimelineScrollRendering: String { case automatic, lazy, eager, native }
