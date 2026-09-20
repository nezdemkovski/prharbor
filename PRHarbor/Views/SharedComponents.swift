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
    let onRebaseStack: (PullRequestStack) async throws -> StackRebaseResult
    var idPrefix: String? = nil

    private var groups: [PullDisplayGroup] {
        groupPullsForDisplay(edges)
    }

    var body: some View {
        ForEach(groups) { group in
            if let stack = group.stack {
                PRStackGroupView(
                    stack: stack,
                    edges: group.edges,
                    config: config,
                    expandedPRUrl: $expandedPRUrl,
                    onRebaseStack: onRebaseStack
                )
                .id(idPrefix.map { "\($0)-stack-\(group.id)" } ?? "stack-\(group.id)")
            } else if let edge = group.edges.first {
                standardRow(edge)
            }
        }
    }

    private func standardRow(_ edge: Edge) -> some View {
        let urlString = edge.node.url.absoluteString
        let isExpanded = !config.clickOpensLink && expandedPRUrl == urlString

        return VStack(spacing: 0) {
            PRRowView(
                pull: edge.node,
                isSelected: isExpanded,
                config: config
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
                PRDetailView(pull: edge.node, config: config)
                    .padding(.horizontal, Theme.rowPaddingH)
                    .padding(.top, 4)
                    .padding(.bottom, Theme.rowPaddingV)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
        .id(idPrefix.map { "\($0)-\(urlString)" } ?? urlString)
    }
}

private struct PRStackGroupView: View {
    let stack: PullRequestStack
    let edges: [Edge]
    let config: PRDisplayConfig
    @Binding var expandedPRUrl: String?
    let onRebaseStack: (PullRequestStack) async throws -> StackRebaseResult

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(edges.enumerated()), id: \.element.node.url) { index, edge in
                PRStackLayerView(
                    edge: edge,
                    config: config,
                    expandedPRUrl: $expandedPRUrl,
                    isFirst: index == 0
                )
            }

            PRStackBaseView(stack: stack, onRebase: onRebaseStack)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stack #\(stack.number), \(stack.size) pull requests into \(stack.baseRefName)")
    }
}

private struct PRStackLayerView: View {
    let edge: Edge
    let config: PRDisplayConfig
    @Binding var expandedPRUrl: String?
    let isFirst: Bool

    private var urlString: String { edge.node.url.absoluteString }
    private var isExpanded: Bool {
        !config.clickOpensLink && expandedPRUrl == urlString
    }

    var body: some View {
        VStack(spacing: 0) {
            PRRowView(
                pull: edge.node,
                isSelected: isExpanded,
                config: config,
                style: .stackLayer(isFirst: isFirst)
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
                PRDetailView(pull: edge.node, config: config)
                    .padding(.horizontal, Theme.rowPaddingH)
                    .padding(.top, 4)
                    .padding(.bottom, Theme.rowPaddingV)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.pending.opacity(0.30))
                            .frame(width: 1.5)
                            .padding(.leading, 4.75)
                            .allowsHitTesting(false)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
    }
}

private enum StackRebaseViewState: Equatable {
    case idle
    case confirming
    case running
    case success(Int)
    case failure(String)
}

private struct PRStackBaseView: View {
    let stack: PullRequestStack
    let onRebase: (PullRequestStack) async throws -> StackRebaseResult

    @State private var rebaseState: StackRebaseViewState = .idle

    private var openPulls: [StackedPullRequest] {
        (stack.entries?.nodes ?? [])
            .compactMap(\.pullRequest)
            .filter { $0.state == "OPEN" }
    }

    private var disabledReason: String? {
        guard (stack.entries?.nodes.count ?? 0) >= stack.size else {
            return "Refresh to load every stack layer"
        }
        if let conflicting = openPulls.first(where: { $0.mergeable == "CONFLICTING" }) {
            return "Resolve conflicts in \(conflicting.headRefName) first"
        }
        guard !openPulls.isEmpty else {
            return "No open pull requests to rebase"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.pending.opacity(0.30))
                        .frame(width: 1.5, height: 9)

                    Circle()
                        .stroke(Theme.neutral, lineWidth: 1.5)
                        .frame(width: 7, height: 7)

                    Spacer(minLength: 0)
                }
                .frame(width: 7, height: 25)

                Text(stack.baseRefName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Spacer(minLength: 8)

                rebaseControls
            }

            statusMessage
                .padding(.leading, 15)
                .font(.system(size: 9.5))
                .lineLimit(2)
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private var rebaseControls: some View {
        switch rebaseState {
        case .idle, .failure:
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    rebaseState = .confirming
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    Text("Rebase stack")
                }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(disabledReason == nil ? Theme.unread : Theme.neutral.opacity(0.65))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(disabledReason != nil)
            .help(disabledReason ?? "Rebase every open branch from the base upward")

        case .confirming:
            HStack(spacing: 7) {
                Button("Cancel") {
                    withAnimation(.snappy(duration: 0.15)) {
                        rebaseState = .idle
                    }
                }
                .foregroundStyle(.secondary)

                Button("Rebase \(openPulls.count)") {
                    performRebase()
                }
                .foregroundStyle(Theme.unread)
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.plain)

        case .running:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Rebasing…")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

        case .success(let count):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Rebased \(count)")
            }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.success)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch rebaseState {
        case .confirming:
            Text("Server-side rebase; new commits won’t be signed")
                .foregroundStyle(.tertiary)
        case .failure(let message):
            Text(message)
                .foregroundStyle(Theme.failure)
        default:
            EmptyView()
        }
    }

    private func performRebase() {
        rebaseState = .running
        Task { @MainActor in
            do {
                let result = try await onRebase(stack)
                withAnimation(.snappy(duration: 0.2)) {
                    rebaseState = .success(result.rebasedCount)
                }
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    rebaseState = .failure(error.localizedDescription)
                }
            }
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
        .frame(minHeight: 20)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
