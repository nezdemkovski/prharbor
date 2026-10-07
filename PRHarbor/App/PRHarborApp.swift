import SwiftUI

@main
struct PRHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var store: PullRequestStore { appDelegate.store }

    var body: some Scene {
        #if DEBUG
        Window(isTimelinePreview ? "PR Harbor — Timeline Preview" : "PR Harbor", id: "timeline-preview") {
            if isTimelinePreview {
                TimelinePreviewHost(store: store)
            } else {
                PanelView(store: store, onQuit: { NSApp.terminate(nil) }, onSettings: appDelegate.showSettings)
            }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(showsDevelopmentWindow ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #endif
        Settings {
            PanelSettingsView(store: store, usernameOverride: isTimelinePreview ? "yuri" : nil)
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

var isTimelinePreview: Bool {
    #if DEBUG
    ProcessInfo.processInfo.environment["PULLBAR_PREVIEW"] == "1"
    #else
    false
    #endif
}

/// Ordinary Debug runs behave like Release. Separate windows are opt-in tools.
var showsDevelopmentWindow: Bool {
    #if DEBUG
    isTimelinePreview || ProcessInfo.processInfo.environment["PULLBAR_DEBUG_WINDOW"] == "1"
    #else
    false
    #endif
}
