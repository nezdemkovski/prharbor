import AppKit
import Defaults
import OSLog
import Testing

@testable import PRHarbor

@Suite("Menu bar panel", .serialized)
@MainActor
struct MenuBarPanelTests {
    @Test func closingThePanelDoesNotQuitTheApp() {
        // The panel popover is usually the only window. SwiftUI asks this before quitting.
        #expect(NSApp.delegate?.applicationShouldTerminateAfterLastWindowClosed?(NSApp) == false)
    }

    @Test func showingAndResizingThePanelLaysOutWithoutRecursion() async throws {
        let logs = try OSLogStore(scope: .currentProcessIdentifier)
        let start = logs.position(date: .now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        let session = GitHubSession(connection: GitHubConnection(username: "yuri", apiBaseURL: Defaults[.githubApiBaseUrl]))
        let store = PullRequestStore(
            startAutomatically: false, session: session, cache: cache,
            clientProvider: { _, _ in throw CancellationError() })
        let edges = TimelinePreviewData.items(now: .now).map { Edge(node: $0.pull) }
        await cache.save(
            PullSnapshot(scope: store.snapshotScope, syncedAt: .now, assigned: [], created: Array(edges.prefix(3)), requested: []))
        await store.loadCachedSnapshot()

        let anchor = NSWindow(
            contentRect: NSRect(x: 200, y: 900, width: 200, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        anchor.isReleasedWhenClosed = false
        defer { anchor.close() }
        anchor.orderFront(nil)
        let bar = StatusBarController(store: store)
        defer { bar.invalidate() }
        bar.showPanel(relativeTo: try #require(anchor.contentView))
        try await Task.sleep(for: .milliseconds(500))
        #expect(bar.isPanelShown)
        let popover = try #require(NSApp.windows.last { $0.className.contains("Popover") && $0.isVisible })
        let initialHeight = popover.frame.height

        // The rows keep one height, so more data scrolls instead of resizing the popover.
        store.clear()
        try await Task.sleep(for: .milliseconds(100))
        await cache.save(PullSnapshot(scope: store.snapshotScope, syncedAt: .now, assigned: [], created: edges, requested: []))
        await store.loadCachedSnapshot()
        try await Task.sleep(for: .milliseconds(500))
        #expect(popover.frame.height == initialHeight)

        // AppKit logs a layout recursion once per process, so this catches the first occurrence.
        // Entries from earlier tests in the same process are not this panel's.
        let recursion = try logs.getEntries(at: start)
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            .filter { $0.contains("already being laid out") }
        #expect(recursion.isEmpty)
    }
}
