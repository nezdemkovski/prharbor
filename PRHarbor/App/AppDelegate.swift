
import Cocoa
import UserNotifications
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var store = PullRequestStore(startAutomatically: !isTimelinePreview && !AppRuntime.isTesting)
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(showsDevelopmentWindow ? .regular : .accessory)
        if isTimelinePreview || AppRuntime.isTesting { return }
        statusBar = StatusBarController(store: store, onSettings: { [weak self] in self?.showSettings() })
        requestNotificationAuthorization()
        UNUserNotificationCenter.current().delegate = self
    }

    func showSettings() {
        statusBar?.closePanel()
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: PanelSettingsView(store: store,
                usernameOverride: isTimelinePreview ? "yuri" : nil).frame(width: 780, height: 568))
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
