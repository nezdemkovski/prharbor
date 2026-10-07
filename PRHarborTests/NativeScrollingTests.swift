import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Native scrolling", .serialized)
struct NativeScrollingTests {
    @Test @MainActor func tabReplacementMountsTheNewViewportInTheSameLayout() async throws {
        let interaction = TimelineInteraction()
        func content(tab: String) -> some View {
            let ids = (0..<68).map { "\(tab):\($0)" }
            let ranges = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, CGFloat(index * 50)..<CGFloat((index + 1) * 50))
            })
            return TimelineNativeScrollView(height: 3_404, rowIDs: ids, ranges: ranges,
                selection: nil, interaction: interaction, content: { id in Text(id).id(id).frame(height: 50) })
                .frame(width: 780, height: 456)
        }
        let hosting = NSHostingController(rootView: content(tab: "all"))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 780, height: 456))
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let scroll = try #require(findScrollView(in: hosting.view))
        let virtual = try #require(scroll.documentView as? any TimelineViewportDocument)
        for tab in ["mine", "reviewing", "all", "mine", "all"] {
            hosting.rootView = content(tab: tab)
            hosting.view.layoutSubtreeIfNeeded()
            // No yield/sleep: a frame must not expose an empty document while
            // waiting for the next main-loop callback or preparation interval.
            #expect(Set((0..<10).map { "\(tab):\($0)" }).isSubset(of: virtual.preparedRowIDs))
            #expect(virtual.preparedRowIDs.allSatisfy { $0.hasPrefix("\(tab):") })
        }
    }

    @Test @MainActor func switchingTabsPreparesVisibleRowsBeforeReturning() throws {
        let document = TimelineVirtualDocumentView { id in Text(id).id(id).frame(height: 50) }
        defer { document.removeRows() }
        // Disjoint tabs and a small result also exercise recycled hosts and the
        // viewport growing again before the deferred prefetch task can run.
        for prefix in ["all", "mine", "reviewing", "all", "mine", "all"] {
            let count = prefix == "mine" ? 3 : 68
            let ids = (0..<count).map { "\(prefix):\($0)" }
            let ranges = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, CGFloat(index * 50)..<CGFloat((index + 1) * 50))
            })
            document.configure(height: CGFloat(count * 50 + 4), rowIDs: ids, ranges: ranges,
                content: { id in Text(id).id(id).frame(height: 50) }, appearance: nil)
            document.refreshViewport(NSRect(x: 0, y: 0, width: 780, height: 100))
            #expect(Set(ids.prefix(2)).isSubset(of: document.preparedRowIDs))
            document.refreshViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
            #expect(Set(ids.prefix(10)).isSubset(of: document.preparedRowIDs))
            #expect(document.preparedRowIDs.isSubset(of: document.mountedRowIDs))
            #expect(document.retainedHostingViewCount <= 42)
            if count == 68 { #expect(document.preparedRowIDs.count < document.mountedRowIDs.count) }
        }
    }

    @Test(arguments: [TimelineScrollRendering.lazy, .eager, .native]) @MainActor
    func scrollingSixtyEightPullsKeepsTheHostingViewportStable(scrollRendering: TimelineScrollRendering) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixtures = TimelinePreviewData.items(now: now)
        let items = (0..<68).map { index -> TimelineItem in
            var pull = fixtures[index % fixtures.count].pull
            pull.number = 10_000 + index
            pull.url = URL(string: "https://github.com/fixture/repo/pull/\(pull.number)")!
            if var stack = pull.stack { stack.id += "-\(index / fixtures.count)"; pull.stack = stack }
            return TimelineItem(pull: pull, username: "yuri", now: now, thresholds: [2, 7, 14], bots: [".*\\[bot\\]"],
                                ownComments: true, snoozedUntil: nil)
        }
        var sizeChanges = 0
        let content = TimelinePanel(store: PullRequestStore(startAutomatically: false), now: now,
            onSettings: {}, onAbout: {}, onQuit: {}, previewItems: items, scrollRendering: scrollRendering)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in sizeChanges += 1 }
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 750))
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let scroll = try #require(findScrollView(in: hosting.view))
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentSize.height)
        let viewport = hosting.view.frame.size
        let initialChanges = sizeChanges
        let maxOffset = document.frame.height - scroll.contentSize.height
        var durations: [Double] = []
        var maximumObservedOffset: CGFloat = 0
        for index in 0..<90 {
            let offset = index % 30 < 15 ? Double(index % 15) / 14 : 1 - Double(index % 15) / 14
            let start = ContinuousClock.now
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maxOffset * offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            hosting.view.layoutSubtreeIfNeeded()
            maximumObservedOffset = max(maximumObservedOffset, scroll.contentView.bounds.origin.y)
            if let virtual = document as? any TimelineViewportDocument {
                #expect(virtual.preparedRowIDs.isSubset(of: virtual.mountedRowIDs))
                #expect(virtual.retainedHostingViewCount <= 42)
            }
            let duration = start.duration(to: .now).components
            durations.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(hosting.view.frame.size == viewport)
        #expect(sizeChanges == initialChanges)
        #expect(maximumObservedOffset > 0)
        if scrollRendering == .native {
            // Only viewport rows and the prefetch margin are mounted, even
            // after traversing the entire list repeatedly.
            let virtual = try #require(document as? any TimelineViewportDocument)
            #expect(virtual.mountedRowIDs.count <= 36)
            #expect(!virtual.mountedRowIDs.isEmpty)
            for _ in 0..<50 where virtual.preparedRowIDs != virtual.mountedRowIDs {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(virtual.preparedRowIDs == virtual.mountedRowIDs)
        }
        let sorted = durations.sorted()
        print("Native scroll layout, rendering=\(scrollRendering.rawValue), 68 PRs, 90 updates: median=\(sorted[45])ms p95=\(sorted[85])ms max=\(sorted.last!)ms")
        window.close()
    }

    // Explicit opt-in: a read-only cache copy supplied by the local profiling
    // runner. Ordinary tests never read production data or perform this replay.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PRHARBOR_PROFILE_SCROLL"] == "1"))
    @MainActor func profileCachedPullsWithDeferredRowPreparation() async throws {
        let environment = ProcessInfo.processInfo.environment
        let input = try #require(environment["PRHARBOR_PROFILE_INPUT"])
        let output = try #require(environment["PRHARBOR_PROFILE_OUTPUT"])
        let cached = try JSONDecoder().decode(PullSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        let now = Date.now
        let items = TimelineInput(assigned: cached.assigned, created: cached.created, requested: cached.requested,
            username: cached.scope.username, now: now, thresholds: [2, 7, 21], bots: ["*[bot]"],
            ownComments: true, snoozed: [:]).makeItems()
        #expect(items.count >= 50)
        let content = TimelinePanel(store: PullRequestStore(startAutomatically: false), now: now,
            onSettings: {}, onAbout: {}, onQuit: {}, previewItems: items, scrollRendering: .native)
            .fixedSize(horizontal: false, vertical: true)
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 780, height: 750))
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let scroll = try #require(findScrollView(in: hosting.view))
        let document = try #require(scroll.documentView)
        let virtual = try #require(document as? any TimelineViewportDocument)
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: URL(fileURLWithPath: output + ".ready"))
        // Give Instruments time to attach to the isolated Release test host.
        try await Task.sleep(for: .seconds(10))
        let maxOffset = max(0, document.frame.height - scroll.contentSize.height)
        var intervals: [Double] = [], synchronous: [Double] = []
        var unpreparedVisible: [Int] = []
        var lastStart = ContinuousClock.now
        let geometry = TimelinePresentation(items: items)
        let initialConfigurations = virtual.configurationCount
        let initialPreparations = virtual.totalPreparedRowCount
        for frame in 0..<1_200 {
            let start = ContinuousClock.now
            let interval = lastStart.duration(to: start).components
            if frame > 0 { intervals.append(Double(interval.seconds) * 1_000 + Double(interval.attoseconds) / 1e15) }
            lastStart = start
            let phase = frame % 240
            let progress = phase < 120 ? CGFloat(phase) / 119 : 1 - CGFloat(phase - 120) / 119
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maxOffset * progress))
            scroll.reflectScrolledClipView(scroll.contentView)
            hosting.view.layoutSubtreeIfNeeded()
            hosting.view.displayIfNeeded()
            let duration = start.duration(to: .now).components
            synchronous.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            let bounds = scroll.contentView.bounds
            let visible = geometry.rows.filter { row in
                geometry.rowRanges[row.id].map { $0.upperBound > bounds.minY && $0.lowerBound < bounds.maxY } ?? false
            }.map(\.id)
            unpreparedVisible.append(visible.filter { !virtual.preparedRowIDs.contains($0) }.count)
            #expect(virtual.preparedRowIDs.isSubset(of: virtual.mountedRowIDs))
            #expect(virtual.retainedHostingViewCount <= 42)
            // Include work queued between updates, unlike the synchronous layout
            // benchmark. This is a CPU/run-loop replay, not display-frame FPS.
            try await Task.sleep(for: .nanoseconds(8_333_333))
        }
        func stats(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["median": sorted[sorted.count / 2], "p95": sorted[Int(Double(sorted.count - 1) * 0.95)],
                "max": sorted.last!, "over16_7ms": Double(values.filter { $0 > 16.7 }.count)]
        }
        let report: [String: Any] = ["pulls": items.count, "rows": geometry.rows.count,
            "synchronous_ms": stats(synchronous), "interval_ms": stats(intervals),
            "frames_with_unprepared_visible_rows": unpreparedVisible.filter { $0 > 0 }.count,
            "maximum_unprepared_visible_rows": unpreparedVisible.max() ?? 0,
            "retained_hosts": virtual.retainedHostingViewCount,
            "configurations_during_replay": virtual.configurationCount - initialConfigurations,
            "rows_prepared_during_replay": virtual.totalPreparedRowCount - initialPreparations]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output))
        print("Scroll replay aggregate report: " + output)
    }

    @Test @MainActor func virtualRowsStayBoundedAndRefreshAfterFiltering() throws {
        let ids = (0..<1_000).map { "row:\($0)" }
        let ranges = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGFloat(index * 50)..<CGFloat((index + 1) * 50))
        })
        let document = TimelineVirtualDocumentView { id in Text(id).id(id).frame(height: 50) }
        document.configure(height: 50_004, rowIDs: ids, ranges: ranges,
            content: { id in Text(id).id(id).frame(height: 50) }, appearance: NSAppearance(named: .aqua))
        document.updateViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
        #expect(document.mountedRowIDs.contains("row:0"))
        #expect(!document.mountedRowIDs.contains("row:999"))
        let height = document.frame.height
        for offset in stride(from: 0, through: 49_500, by: 100) {
            let viewport = NSRect(x: 0, y: offset, width: 780, height: 456)
            document.updateViewport(viewport)
            #expect(document.mountedRowIDs.count <= 36)
            #expect(document.frame.height == height)
            let currentRow = "row:\(offset / 50)"
            #expect(document.mountedRowIDs.contains(currentRow))
        }
        #expect(document.mountedRowIDs.contains("row:999"))
        document.updateViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
        #expect(document.mountedRowIDs.contains("row:0"))
        #expect(!document.mountedRowIDs.contains("row:999"))
        document.configure(height: 54, rowIDs: ["row:999"], ranges: ["row:999": 0..<50],
            content: { id in Text(id).id(id).frame(height: 50) }, appearance: NSAppearance(named: .darkAqua))
        document.updateViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
        #expect(document.mountedRowIDs == ["row:999"])
        #expect(document.frame.height == 54)
        document.configure(height: 4, rowIDs: [], ranges: [:],
            content: { id in Text(id).id(id).frame(height: 50) }, appearance: nil)
        document.updateViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
        #expect(document.mountedRowIDs.isEmpty)
    }

    @Test @MainActor func aFastJumpCancelsRowsFromThePreviousViewport() async throws {
        let ids = (0..<1_000).map { "row:\($0)" }
        let ranges = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGFloat(index * 50)..<CGFloat((index + 1) * 50))
        })
        let document = TimelineVirtualDocumentView { id in Text(id).id(id).frame(height: 50) }
        document.configure(height: 50_004, rowIDs: ids, ranges: ranges,
            content: { id in Text(id).id(id).frame(height: 50) }, appearance: nil)
        document.updateViewport(NSRect(x: 0, y: 0, width: 780, height: 456))
        document.updateViewport(NSRect(x: 0, y: 49_500, width: 780, height: 456))
        try await Task.sleep(for: .milliseconds(400))
        #expect(document.preparedRowIDs.contains("row:999"))
        #expect(!document.preparedRowIDs.contains("row:0"))
        #expect(document.preparedRowIDs.isSubset(of: document.mountedRowIDs))
        #expect(document.retainedHostingViewCount <= 42)
        document.removeRows()
        try await Task.sleep(for: .milliseconds(40))
        #expect(document.preparedRowIDs.isEmpty)
        #expect(document.retainedHostingViewCount == 0)
    }

    @Test @MainActor func keyboardSelectionMountsAnOffscreenRow() async throws {
        let ids = (0..<100).map { "row:\($0)" }
        let ranges = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGFloat(index * 50)..<CGFloat((index + 1) * 50))
        })
        let interaction = TimelineInteraction()
        func content(selection: String?) -> some View {
            TimelineNativeScrollView(height: 5_004, rowIDs: ids, ranges: ranges,
                selection: selection, interaction: interaction, content: { id in Text(id).id(id).frame(height: 50) })
                .frame(width: 780, height: 456)
        }
        let hosting = NSHostingController(rootView: content(selection: "row:0"))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 780, height: 456))
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let scroll = try #require(findScrollView(in: hosting.view))
        let document = try #require(scroll.documentView)
        let virtual = try #require(document as? any TimelineViewportDocument)
        #expect(!virtual.mountedRowIDs.contains("row:99"))
        hosting.rootView = content(selection: "row:99")
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(virtual.mountedRowIDs.contains("row:99"))
        #expect(scroll.contentView.bounds.maxY >= 5_000)
        hosting.rootView = content(selection: "row:0")
        hosting.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(virtual.mountedRowIDs.contains("row:0"))
        #expect(scroll.contentView.bounds.minY == 0)
    }

    @MainActor private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews { if let scroll = findScrollView(in: child) { return scroll } }
        return nil
    }
}
