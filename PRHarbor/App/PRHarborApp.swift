import SwiftUI

@main
struct PRHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = PullRequestStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store, onQuit: { NSApp.terminate(nil) })
        } label: {
            Image("git-pull-request")
            if store.totalCount > 0 {
                Text("\(store.totalCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
