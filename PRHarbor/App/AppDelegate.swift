import Cocoa
import Defaults
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.current
    lazy var store: PullRequestStore = {
        let services = AppServices(runtime: runtime)
        return PullRequestStore(startAutomatically: services.startsSync, session: services.session, cache: services.cache)
    }()
    private var statusBar: StatusBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before launch completes, so a notification click that launched the app is delivered.
        if runtime == .production { UNUserNotificationCenter.current().delegate = self }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(runtime.showsDevelopmentWindow ? .regular : .accessory)
        guard runtime == .production else { return }
        let session = store.session
        Task { await session.restoreFromSavedToken(baseURL: Defaults[.githubApiBaseUrl]) }
        statusBar = StatusBarController(store: store)
        NotificationDelivery.register()
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
        let opens =
            response.actionIdentifier == UNNotificationDefaultActionIdentifier
            || response.actionIdentifier == NotificationDelivery.openAction
        let url = (userInfo["url"] as? String).flatMap(URL.init(string:))
        DispatchQueue.main.async { [weak self] in
            guard opens else { return }
            // A pull request opens on GitHub; summaries and the test notification open the panel.
            if let url { NSWorkspace.shared.open(url) } else { self?.statusBar?.showPanel() }
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
