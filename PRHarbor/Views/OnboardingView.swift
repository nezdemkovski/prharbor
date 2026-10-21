import SwiftUI

struct OnboardingView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: Spacing.section) {
            Spacer()

            Image("git-pull-request")
                .resizable()
                .frame(width: Size.onboardingGlyph, height: Size.onboardingGlyph)
                .opacity(Opacity.decorativeGlyph)

            VStack(spacing: Spacing.s) {
                Text("Welcome to PR Harbor")
                    .font(.ui(Typography.title, .bold))
                Text("Keep track of your GitHub pull requests\nright from the menu bar.")
                    .font(.ui(Typography.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingFeature(icon: "bell.badge", color: Palette.accent, text: "Get notified about new PRs")
                OnboardingFeature(icon: "checkmark.circle", color: Palette.success, text: "Track CI status and reviews")
                OnboardingFeature(icon: "arrow.triangle.branch", color: Palette.staleFill, text: "Copy branch names instantly")
            }
            .padding(.horizontal, Spacing.wide)

            Button {
                onConnect()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "key")
                    Text("Add GitHub Token")
                }
                .font(.ui(Typography.callout, .semibold))
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
        HStack(spacing: Spacing.l) {
            Image(systemName: icon)
                .font(.ui(Typography.body))
                .foregroundStyle(color)
                .frame(width: Size.statusIcon)
            Text(text)
                .font(.ui(Typography.subheadline))
                .foregroundStyle(.secondary)
        }
    }
}
