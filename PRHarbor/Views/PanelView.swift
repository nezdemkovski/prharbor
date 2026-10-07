import SwiftUI
import Defaults

struct PanelView: View {
    @ObservedObject var store: PullRequestStore
    var onQuit: () -> Void
    var onSettings: (() -> Void)? = nil
    var onSizeChange: ((CGSize) -> Void)? = nil
    @Environment(\.openSettings) private var openSettings
    @State private var showingAbout = false

    var body: some View {
        Group {
            if store.isConfigured {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    TimelinePanel(store: store, now: context.date, onSettings: settings, onAbout: { showingAbout = true }, onQuit: onQuit)
                }
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
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
            onSizeChange?(size)
        }
        .background(TimelineStyle.panel)
        .sheet(isPresented: $showingAbout) {
            VStack { AboutView(); Button("Done") { showingAbout = false }.keyboardShortcut(.defaultAction).padding() }.frame(width: 420, height: 380)
        }
    }
    private func settings() {
        if let onSettings { onSettings() }
        else { NSApp.activate(); openSettings() }
    }
}
