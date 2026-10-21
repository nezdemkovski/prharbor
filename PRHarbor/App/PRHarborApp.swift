import SwiftUI

@main
struct PRHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var store: PullRequestStore { appDelegate.store }

    var body: some Scene {
        #if DEBUG
        Window(AppRuntime.current == .timelinePreview ? "PR Harbor — Timeline Preview" : "PR Harbor", id: "timeline-preview") {
            if AppRuntime.current == .timelinePreview {
                TimelinePreviewHost(store: store)
            } else {
                PanelView(store: store, onQuit: { NSApp.terminate(nil) })
            }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(AppRuntime.current.showsDevelopmentWindow ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #endif
        Settings {
            SettingsView(store: store, usernameOverride: AppRuntime.current.usernameOverride)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
