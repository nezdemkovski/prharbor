import AppKit

/// Tells the virtual document where the viewport is, and the timeline whether a live scroll is
/// under way, so hover does not follow rows moving under a still pointer.
@MainActor final class TimelineAppKitScrollView: NSScrollView {
    weak var interaction: TimelineInteraction?
    private var liveScrollObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let center = NotificationCenter.default
        liveScrollObservers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScrolling(true) }
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScrolling(false) }
            }
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        for observer in liveScrollObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        (documentView as? any TimelineViewportDocument)?.updateViewport(clipView.bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setScrolling(false)
    }

    private func setScrolling(_ scrolling: Bool) {
        interaction?.isScrolling = scrolling
        if scrolling { interaction?.cursorAge = nil }
    }
}
