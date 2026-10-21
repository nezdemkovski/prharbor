
import Cocoa
import UserNotifications
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.current
    lazy var store: PullRequestStore = {
        let services = AppServices(runtime: runtime)
        return PullRequestStore(startAutomatically: services.startsSync, session: services.session, cache: services.cache)
    }()
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(runtime.showsDevelopmentWindow ? .regular : .accessory)
        guard runtime == .production else { return }
        statusBar = StatusBarController(store: store, onSettings: { [weak self] in self?.showSettings() })
        requestNotificationAuthorization()
        UNUserNotificationCenter.current().delegate = self
    }

    func showSettings() {
        statusBar?.closePanel()
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: PanelSettingsView(store: store,
                usernameOverride: runtime.usernameOverride).frame(width: 780, height: 568))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "PR Harbor Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 780, height: 568))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) { statusBar?.invalidate() }

    /// A menu bar app outlives its windows. Without this, SwiftUI quits when the panel
    /// popover, the only window, closes (Debug builds declare a Window scene).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier ||
           response.actionIdentifier == "OPEN_PR",
           let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
