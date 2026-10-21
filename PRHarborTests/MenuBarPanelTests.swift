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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        let session = GitHubSession(connection: GitHubConnection(username: "yuri", apiBaseURL: Defaults[.githubApiBaseUrl]))
        let store = PullRequestStore(startAutomatically: false, session: session, cache: cache,
                                     clientProvider: { _, _ in throw CancellationError() })
        let edges = TimelinePreviewData.items(now: .now).map { Edge(node: $0.pull) }
        await cache.save(PullSnapshot(scope: store.snapshotScope, syncedAt: .now, assigned: [], created: Array(edges.prefix(3)), requested: []))
        await store.loadCachedSnapshot()

        let anchor = NSWindow(contentRect: NSRect(x: 200, y: 900, width: 200, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        anchor.isReleasedWhenClosed = false
        defer { anchor.close() }
        anchor.orderFront(nil)
        let bar = StatusBarController(store: store, onSettings: {})
        defer { bar.invalidate() }
        bar.showPanel(relativeTo: try #require(anchor.contentView))
        try await Task.sleep(for: .milliseconds(500))
        #expect(bar.isPanelShown)

        // Growing the data grows the panel, which resizes the popover again.
        await cache.save(PullSnapshot(scope: store.snapshotScope, syncedAt: .now.addingTimeInterval(1), assigned: [], created: edges, requested: []))
        store.clear()
        await store.loadCachedSnapshot()
        try await Task.sleep(for: .milliseconds(500))

        // AppKit logs a layout recursion once per process, so this catches the first occurrence.
        let recursion = try OSLogStore(scope: .currentProcessIdentifier).getEntries()
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            .filter { $0.contains("already being laid out") }
        #expect(recursion.isEmpty)
    }
}
