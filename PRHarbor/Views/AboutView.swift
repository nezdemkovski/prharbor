
import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image(nsImage: NSImage(named: "AppIcon")!)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(spacing: 4) {
                    Text("PR Harbor")
                        .font(.system(size: 20, weight: .bold))
                    Text("v\(currentVersion)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer().frame(height: 28)

            VStack(spacing: 16) {
                Text("GitHub pull requests\nin your menu bar")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                VStack(alignment: .leading, spacing: 8) {
                    featureRow(icon: "bell.badge", color: Theme.unread, text: "Notifications for new PRs")
                    featureRow(icon: "checkmark.circle", color: Theme.success, text: "CI status and review tracking")
                    featureRow(icon: "magnifyingglass", color: Theme.neutral, text: "Search and filter across repos")
                    featureRow(icon: "arrow.triangle.branch", color: Theme.stale, text: "Quick copy branch & URL")
                    featureRow(icon: "puzzlepiece.extension.fill", color: Theme.unread, text: "Group PRs into features across repos")
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    aboutPill(icon: "chevron.left.forwardslash.chevron.right", text: "GitHub", url: "https://github.com/nezdemkovski/prharbor")
                    aboutPill(icon: "globe", text: "nezdemkovski.com", url: "https://nezdemkovski.com")
                }

                Text("by Yuri Nezdemkovski")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func aboutPill(icon: String, text: String, url: String) -> some View {
        Button {
            openURL(URL(string: url)!)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(text)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutView()
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
}
