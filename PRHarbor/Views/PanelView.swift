import SwiftUI

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
                    }.padding(Spacing.panel)
                    Divider()
                    OnboardingView(onConnect: settings)
                }
            }
        }
        .frame(width: TimelineMetrics.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The panel belongs to an accessory app, so activate it before bringing the Settings scene forward.
    private func settings() {
        NSApp.activate()
        openSettings()
    }
}
