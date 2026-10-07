import SwiftUI

struct OnboardingView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("git-pull-request")
                .resizable()
                .frame(width: 36, height: 36)
                .opacity(0.5)

            VStack(spacing: 6) {
                Text("Welcome to PR Harbor")
                    .font(.system(size: 16, weight: .bold))
                Text("Keep track of your GitHub pull requests\nright from the menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingFeature(icon: "bell.badge", color: Theme.unread, text: "Get notified about new PRs")
                OnboardingFeature(icon: "checkmark.circle", color: Theme.success, text: "Track CI status and reviews")
                OnboardingFeature(icon: "arrow.triangle.branch", color: Theme.stale, text: "Copy branch names instantly")
            }
            .padding(.horizontal, 40)

            Button {
                onConnect()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                    Text("Connect GitHub CLI")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingFeature: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}
