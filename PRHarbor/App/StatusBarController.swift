import AppKit
import Combine
import SwiftUI

/// Own the public AppKit status item so primary and secondary clicks have
/// separate actions. The panel itself remains the existing SwiftUI view.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let menu = NSMenu()
    private let store: PullRequestStore
    private var countObservation: AnyCancellable?

    init(store: PullRequestStore, onSettings: @escaping () -> Void) {
        self.store = store
        super.init()

        statusItem.autosaveName = "PRHarbor"
        if let button = statusItem.button {
            button.image = NSImage(named: "git-pull-request")
            button.image?.size = NSSize(width: 18, height: 18)
            button.imagePosition = .imageLeading
            button.toolTip = "PR Harbor"
            button.setAccessibilityLabel("PR Harbor")
            button.setAccessibilityIdentifier("prharbor-status-item")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApplication(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        let hosting = NSHostingController(rootView: PanelView(store: store,
            onQuit: { NSApp.terminate(nil) }, onSettings: onSettings,
            onSizeChange: { [weak self] size in self?.resizePanel(to: size) }))
        // The SwiftUI panel reports its explicit bounds only when they change.
        // Ideal-size tracking would measure the lazy scroll content during scrolling.
        hosting.sizingOptions = []
        hosting.view.frame.size = NSSize(width: Theme.panelWidth, height: 274)
        popover.contentSize = hosting.view.frame.size
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false

        updateCount()
        // Deliver after @Published has changed so the count reflects the new data.
        countObservation = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.updateCount()
        }
    }

    private func resizePanel(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        if popover.contentSize != rounded { popover.contentSize = rounded }
    }

    func showPanel() {
        guard let button = statusItem.button, !popover.isShown else { return }
        store.refresh(respectFreshness: true)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePanel() { popover.performClose(nil) }

    func invalidate() {
        closePanel()
        countObservation = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateCount() {
        let count = store.totalCount
        let title = count > 0 ? " \(count)" : ""
        if statusItem.button?.title != title { statusItem.button?.title = title }
        statusItem.button?.setAccessibilityValue("\(count) pull requests")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            closePanel()
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else if popover.isShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    @objc private func quitApplication(_ sender: Any?) { NSApp.terminate(sender) }
}
