import AppKit
import Observation
import SwiftUI

/// Own the public AppKit status item so primary and secondary clicks have
/// separate actions. The panel itself remains the existing SwiftUI view.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let menu = NSMenu()
    private let store: PullRequestStore
    private var countObservation: Task<Void, Never>?

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
            onQuit: { [weak self] in self?.quit() }, onSettings: onSettings,
            onSizeChange: { [weak self] size in self?.resizePanel(to: size) }))
        // The SwiftUI panel reports its explicit bounds only when they change.
        // Ideal-size tracking would measure the lazy scroll content during scrolling.
        hosting.sizingOptions = []
        hosting.view.frame.size = NSSize(width: Theme.panelWidth, height: 274)
        popover.contentSize = hosting.view.frame.size
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false

        countObservation = Task { [weak self, store] in
            for await count in Observations({ store.totalCount }) { self?.updateCount(count) }
        }
    }

    /// Geometry callbacks arrive during SwiftUI's layout. Resizing the popover there lays out
    /// its window recursively, which AppKit reports as illegal, so it waits for the next turn.
    private func resizePanel(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        DispatchQueue.main.async { [weak self] in
            guard let self, popover.contentSize != rounded else { return }
            popover.contentSize = rounded
        }
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        showPanel(relativeTo: button)
    }

    func showPanel(relativeTo anchor: NSView) {
        guard !popover.isShown else { return }
        store.refresh(respectFreshness: true)
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    var isPanelShown: Bool { popover.isShown }

    func closePanel() { popover.performClose(nil) }

    /// The popover's window belongs to AppKit; closing it through the popover first keeps
    /// termination from closing it as an ordinary window. The status item leaves with the process.
    func invalidate() {
        popover.close()
        countObservation?.cancel()
        countObservation = nil
    }

    private func quit() {
        popover.close()
        NSApp.terminate(nil)
    }

    private func updateCount(_ count: Int) {
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

    @objc private func quitApplication(_ sender: Any?) { quit() }
}
