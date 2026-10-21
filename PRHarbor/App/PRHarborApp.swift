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
                PanelView(store: store, onQuit: { NSApp.terminate(nil) }, onSettings: appDelegate.showSettings)
            }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(AppRuntime.current.showsDevelopmentWindow ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #endif
        Settings {
            PanelSettingsView(store: store, usernameOverride: AppRuntime.current.usernameOverride)
                .frame(width: 780, height: 568)
        }.windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…", action: appDelegate.showSettings).keyboardShortcut(",")
            }
        }
    }
}
