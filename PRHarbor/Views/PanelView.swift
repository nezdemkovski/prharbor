import SwiftUI
import Defaults

struct PanelView: View {
    let store: PullRequestStore
    var onQuit: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if store.isConfigured {
                TimelinePanel(store: store, now: store.now, onSettings: settings, onAbout: showAboutPanel, onQuit: onQuit)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("PR Harbor").font(.headline)
                        Spacer()
                        Button("Settings…", action: settings)
                    }.padding(18)
                    Divider()
                    OnboardingView(onConnect: settings)
                }
            }
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The panel belongs to an accessory app, so activate it before bringing the Settings scene forward.
    private func settings() {
        NSApp.activate()
        openSettings()
    }
}

/// The standard About window, with the project's links as credits.
@MainActor func showAboutPanel() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                                .paragraphStyle: paragraph]
    let credits = NSMutableAttributedString(string: "GitHub pull requests in your menu bar.\nby Yuri Nezdemkovski\n\n", attributes: base)
    for (index, (title, address)) in [("GitHub", "https://github.com/nezdemkovski/prharbor"), ("nezdemkovski.com", "https://nezdemkovski.com")].enumerated() {
        if index > 0 { credits.append(NSAttributedString(string: "  ·  ", attributes: base)) }
        var link = base
        link[.link] = URL(string: address)
        credits.append(NSAttributedString(string: title, attributes: link))
    }
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}
