import AppKit

@MainActor final class TimelineAppKitScrollView: NSScrollView {
    weak var interaction: TimelineInteraction?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        (documentView as? any TimelineViewportDocument)?.updateViewport(clipView.bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        interaction?.isScrolling = false
    }

    override func scrollWheel(with event: NSEvent) {
        let ended = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
            || (event.momentumPhase.isEmpty && (event.phase.contains(.ended) || event.phase.contains(.cancelled)))
        interaction?.isScrolling = !ended
        if !ended { interaction?.cursorAge = nil }
        super.scrollWheel(with: event)
        if ended || (event.phase.isEmpty && event.momentumPhase.isEmpty) { interaction?.isScrolling = false }
    }
}
