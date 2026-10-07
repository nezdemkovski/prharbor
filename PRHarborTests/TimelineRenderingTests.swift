import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Native timeline rendering", .serialized)
struct TimelineRenderingTests {
    @Test @MainActor func ordinaryDebugLaunchStaysInTheMenuBar() {
        #expect(NSApp.activationPolicy() == .accessory)
        #expect(!NSApp.windows.contains {
            $0.isVisible && ($0.identifier?.rawValue == "timeline-preview" || $0.title == "PR Harbor")
        })
    }

    @Test @MainActor func rendersLightAndDarkPanels() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = PullRequestStore(startAutomatically: false)
        for scheme in [ColorScheme.light, .dark] {
            let content = TimelinePanel(store: store, now: now, onSettings: {}, onAbout: {}, onQuit: {}, previewItems: TimelinePreviewData.items(now: now))
                .frame(width: 780, height: 750)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let hosting = NSHostingView(rootView: content)
            hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 750)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/pullbar-preview-\(scheme == .light ? "light" : "dark").png"))
            #expect(bitmap.pixelsWide >= 780)
            window.close()
        }
    }
    @Test @MainActor func rendersSettingsAndEmptyStates() async throws {
        let store = PullRequestStore(startAutomatically: false)
        let settings = NSHostingView(rootView: PanelSettingsView(store: store).frame(width: 780, height: 600).environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        try await snapshot(settings, name: "settings", size: CGSize(width: 780, height: 600))
        for destination in SettingsDestination.allCases where destination != .account {
            let pane = NSHostingView(rootView: TimelineSettingsPane(destination: destination, store: store).frame(width: 550, height: 550).environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
            try await snapshot(pane, name: "settings-" + destination.rawValue.replacingOccurrences(of: " ", with: "-"), size: CGSize(width: 550, height: 550))
        }
        let empty = NSHostingView(rootView: TimelinePanel(store: store, now: .now, onSettings: {}, onAbout: {}, onQuit: {}, previewItems: []).frame(width: 780, height: 750).environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        try await snapshot(empty, name: "empty", size: CGSize(width: 780, height: 750))
        store.error = "Unable to reach GitHub. Your last synced pull requests are still available."
        let error = NSHostingView(rootView: TimelinePanel(store: store, now: .now, onSettings: {}, onAbout: {}, onQuit: {}, previewItems: TimelinePreviewData.items(now: .now)).frame(width: 780, height: 750).environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        try await snapshot(error, name: "error", size: CGSize(width: 780, height: 750))
    }
    @MainActor private func snapshot<V: View>(_ hosting: NSHostingView<V>, name: String, size: CGSize) async throws {
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/pullbar-preview-" + name + ".png"))
        window.close()
    }

}
