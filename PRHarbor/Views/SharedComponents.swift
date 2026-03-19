import SwiftUI


struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CircleIconButton: View {
    let icon: String
    let size: CGFloat
    let frameSize: CGFloat
    let color: Color
    let background: Color
    let action: () -> Void
    var help: String? = nil

    init(icon: String, size: CGFloat = 10, frameSize: CGFloat = 20, color: Color = .secondary, background: Color = Theme.cardBackground, help: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.frameSize = frameSize
        self.color = color
        self.background = background
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(color)
                .frame(width: frameSize, height: frameSize)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

struct PRRowsContainer: View {
    let edges: [Edge]
    let config: PRDisplayConfig
    @Binding var expandedPRUrl: String?
    var onAddToFeature: ((String) -> Void)? = nil
    var idPrefix: String? = nil

    var body: some View {
        ForEach(edges, id: \.node.url) { edge in
            let urlString = edge.node.url.absoluteString
            let isExpanded = !config.clickOpensLink && expandedPRUrl == urlString

            VStack(spacing: 0) {
                PRRowView(
                    pull: edge.node,
                    isSelected: isExpanded,
                    config: config,
                    onAddToFeature: onAddToFeature != nil ? { onAddToFeature?(urlString) } : nil
                ) {
                    if config.clickOpensLink {
                        NSWorkspace.shared.open(edge.node.url)
                    } else {
                        withAnimation(.snappy(duration: 0.25)) {
                            expandedPRUrl = isExpanded ? nil : urlString
                        }
                    }
                }

                if isExpanded {
                    PRDetailView(pull: edge.node)
                        .padding(.horizontal, Theme.rowPaddingH)
                        .padding(.top, 4)
                        .padding(.bottom, Theme.rowPaddingV)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
            .id(idPrefix.map { "\($0)-\(urlString)" } ?? urlString)
        }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
    }
}

struct CollapsibleHeader<Trailing: View>: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        count: Int,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            }
            .buttonStyle(.plain)
            .frame(width: 12)

            SectionTitle(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            VStack { Divider().opacity(0.3) }

            trailing
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

struct HeaderConfirmBar: View {
    let message: String
    let action: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onConfirm) {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDestructive ? Theme.failure : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isDestructive ? Theme.failure.opacity(0.1) : Theme.tabSelected, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.cardBackground, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.headerPaddingH)
            .padding(.vertical, 6)
            Divider().opacity(0.5)
        }
        .background(Theme.cardBackground)
    }
}

struct HeaderInputBar: View {
    let label: String
    @Binding var text: String
    let action: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Name...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(onSubmit)
                Button(action: onSubmit) {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.tabSelected, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.headerPaddingH)
            .padding(.vertical, 6)
            Divider().opacity(0.5)
        }
        .background(Theme.cardBackground)
    }
}

struct HeaderIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovering ? Theme.hoverBackground : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct TabPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.tabSelected : isHovering ? Theme.hoverBackground : .clear)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct PRScrollContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                content
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }
}

struct OnboardingView: View {
    let onSignIn: () -> Void

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
                onSignIn()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.key")
                    Text("Sign in with GitHub")
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
