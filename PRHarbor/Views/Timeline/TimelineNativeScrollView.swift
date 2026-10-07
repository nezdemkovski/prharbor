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

@MainActor protocol TimelineViewportDocument: AnyObject {
    var mountedRowIDs: Set<String> { get }
    var preparedRowIDs: Set<String> { get }
    var retainedHostingViewCount: Int { get }
    var configurationCount: Int { get }
    var totalPreparedRowCount: Int { get }
    func updateViewport(_ bounds: NSRect)
}

/// The document is lightweight AppKit geometry. Heavy SwiftUI row trees are
/// prepared ahead of the viewport, one per interval; scrolling only moves the
/// clip bounds and recycles offscreen hosts. It never publishes SwiftUI state.
@MainActor final class TimelineVirtualDocumentView<Content: View>: NSView, TimelineViewportDocument {
    override var isFlipped: Bool { true }
    private var rowIDs: [String] = []
    private var ranges: [String: Range<CGFloat>] = [:]
    private var needed: [String] = []
    private var content: (String) -> Content
    private var placeholder: (String) -> TimelineRowPlaceholder = { _ in TimelineRowPlaceholder(title: "", subtitle: "") }
    private var activate: (String) -> Void = { _ in }
    private var hosts: [String: NSHostingView<Content>] = [:]
    private var pool: [NSHostingView<Content>] = []
    private var isConfiguring = false
    private var preparationTask: Task<Void, Never>?
    private var preparationGeneration = 0
    private var needsViewportRefresh = false
    private(set) var configurationCount = 0
    private(set) var totalPreparedRowCount = 0
    var mountedRowIDs: Set<String> { Set(needed) }
    var preparedRowIDs: Set<String> { Set(hosts.keys) }
    var retainedHostingViewCount: Int { hosts.count + pool.count }

    init(content: @escaping (String) -> Content) {
        self.content = content
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(height: CGFloat, rowIDs: [String], ranges: [String: Range<CGFloat>],
                   content: @escaping (String) -> Content,
                   placeholder: @escaping (String) -> TimelineRowPlaceholder = { _ in TimelineRowPlaceholder(title: "", subtitle: "") },
                   activate: @escaping (String) -> Void = { _ in }, appearance: NSAppearance?) {
        configurationCount += 1
        isConfiguring = true
        defer { isConfiguring = false }
        stopLoading()
        self.rowIDs = rowIDs
        self.ranges = ranges
        self.content = content
        self.placeholder = placeholder
        self.activate = activate
        self.appearance = appearance
        frame.size = NSSize(width: TimelineMetrics.panelWidth, height: max(1, height))
        for id in Array(hosts.keys) where ranges[id] == nil { recycle(id) }
        for (id, host) in hosts {
            host.rootView = content(id)
            position(host, id: id)
        }
        needsViewportRefresh = true
        needsDisplay = true
    }

    func refreshViewport(_ bounds: NSRect) { updateViewport(bounds, prepareVisibleImmediately: true) }
    func updateViewport(_ bounds: NSRect) { updateViewport(bounds, prepareVisibleImmediately: false) }
    private func updateViewport(_ bounds: NSRect, prepareVisibleImmediately: Bool) {
        guard !isConfiguring else { return }
        let lower = max(0, bounds.minY - 240)
        let upper = min(frame.height, bounds.maxY + 240)
        var first = 0
        var end = rowIDs.count
        while first < end {
            let middle = (first + end) / 2
            if (ranges[rowIDs[middle]]?.upperBound ?? 0) <= lower { first = middle + 1 }
            else { end = middle }
        }
        let batchSize = 6
        first = (first / batchSize) * batchSize
        var last = first
        if bounds.height > 0 {
            while last < rowIDs.count, (ranges[rowIDs[last]]?.lowerBound ?? frame.height) < upper { last += 1 }
            last = min(rowIDs.count, ((last + batchSize - 1) / batchSize) * batchSize)
        }
        let next = bounds.height > 0 ? Array(rowIDs[first..<last]) : []
        let prepareVisible = prepareVisibleImmediately || needsViewportRefresh
        let visible = next.filter { id in
            ranges[id].map { $0.upperBound > bounds.minY && $0.lowerBound < bounds.maxY } ?? false
        }
        guard next != needed || needsViewportRefresh || (prepareVisible && visible.contains { hosts[$0] == nil }) else { return }
        needsViewportRefresh = bounds.height == 0
        needed = next
        let ids = Set(next)
        for id in Array(hosts.keys) where !ids.contains(id) { recycle(id) }
        if pool.count > 6 { pool.removeLast(pool.count - 6) }
        needsDisplay = true
        stopLoading()
        // Tab/filter/data updates are discrete changes. Their visible rows must
        // appear together; only scrolling and offscreen prefetch use the queue.
        if prepareVisible {
            for id in visible where hosts[id] == nil { prepare(id) }
            for id in visible { hosts[id]?.layoutSubtreeIfNeeded() }
        }
        let pending = next.filter { hosts[$0] == nil }.sorted { a, b in
            let aVisible = ranges[a].map { $0.upperBound > bounds.minY && $0.lowerBound < bounds.maxY } ?? false
            let bVisible = ranges[b].map { $0.upperBound > bounds.minY && $0.lowerBound < bounds.maxY } ?? false
            if aVisible != bVisible { return aVisible }
            return (ranges[a]?.lowerBound ?? 0) < (ranges[b]?.lowerBound ?? 0)
        }
        guard !pending.isEmpty else { return }
        let generation = preparationGeneration
        preparationTask = Task { @MainActor [weak self] in
            await Task.yield()
            for id in pending {
                guard !Task.isCancelled, let self, self.preparationGeneration == generation else { return }
                self.prepare(id)
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    private func prepare(_ id: String) {
        guard let range = ranges[id] else { return }
        totalPreparedRowCount += 1
        let host: NSHostingView<Content>
        if let recycled = pool.popLast() { host = recycled; host.rootView = content(id) }
        else { host = NSHostingView(rootView: content(id)); host.sizingOptions = [] }
        position(host, id: id)
        hosts[id] = host
        addSubview(host)
        setNeedsDisplay(NSRect(x: 0, y: range.lowerBound, width: frame.width, height: range.upperBound - range.lowerBound))
    }

    private func position(_ host: NSHostingView<Content>, id: String) {
        guard let range = ranges[id] else { return }
        host.frame = NSRect(x: 0, y: range.lowerBound, width: TimelineMetrics.panelWidth,
                            height: range.upperBound - range.lowerBound)
    }
    private func recycle(_ id: String) {
        guard let host = hosts.removeValue(forKey: id) else { return }
        host.removeFromSuperview()
        pool.append(host)
    }
    func stopLoading() {
        preparationGeneration += 1
        preparationTask?.cancel()
        preparationTask = nil
    }
    func removeRows() {
        stopLoading()
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll(); pool.removeAll(); needed.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Lightweight titles stay readable during a fling while the detailed
        // timeline is preparing. Their rectangles are identical to final rows.
        for id in needed where hosts[id] == nil {
            guard let range = ranges[id] else { continue }
            let rect = NSRect(x: 0, y: range.lowerBound, width: frame.width, height: range.upperBound - range.lowerBound)
            guard rect.intersects(dirtyRect) else { continue }
            let preview = placeholder(id)
            let x: CGFloat = preview.isRepository ? 18 : 58
            let title = NSAttributedString(string: preview.title, attributes: [
                .font: NSFont.systemFont(ofSize: preview.isRepository ? 12 : 13, weight: .medium),
                .foregroundColor: preview.isRepository ? NSColor.secondaryLabelColor : NSColor.labelColor])
            title.draw(in: NSRect(x: x, y: rect.minY + 9, width: 230, height: 17))
            if !preview.isRepository {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 18, y: rect.minY + 10, width: 30, height: 30)).fill()
                NSAttributedString(string: preview.subtitle, attributes: [.font: NSFont.systemFont(ofSize: 11.5),
                    .foregroundColor: NSColor.secondaryLabelColor])
                    .draw(in: NSRect(x: x, y: rect.minY + 26, width: 230, height: 15))
                NSColor.quaternaryLabelColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: NSRect(x: 288, y: rect.minY + 9, width: TimelineMetrics.trackWidth, height: 32),
                             xRadius: 10, yRadius: 10).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        if let id = needed.first(where: { ranges[$0]?.contains(y) == true }), hosts[id] == nil { activate(id) }
        else { super.mouseDown(with: event) }
    }
}

nonisolated struct TimelineRowPlaceholder {
    let title: String
    let subtitle: String
    var isRepository = false
}

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

nonisolated enum TimelineScrollRendering: String { case automatic, lazy, eager, native }
