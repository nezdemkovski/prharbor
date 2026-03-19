import SwiftUI


struct PRDisplayConfig: Equatable {
    let showAvatar: Bool
    let showUnreadDot: Bool
    let showLinesChanged: Bool
    let showApprovals: Bool
    let clickOpensLink: Bool
    let githubUsername: String
    let staleDays: Int
    let staleDate: Date?

    init(showAvatar: Bool, showUnreadDot: Bool, showLinesChanged: Bool, showApprovals: Bool, clickOpensLink: Bool, githubUsername: String, staleDays: Int) {
        self.showAvatar = showAvatar
        self.showUnreadDot = showUnreadDot
        self.showLinesChanged = showLinesChanged
        self.showApprovals = showApprovals
        self.clickOpensLink = clickOpensLink
        self.githubUsername = githubUsername
        self.staleDays = staleDays
        self.staleDate = staleDays > 0 ? Calendar.current.date(byAdding: .day, value: -staleDays, to: Date()) : nil
    }
}


struct PRRowView: View, Equatable {
    let pull: Pull
    let isSelected: Bool
    let config: PRDisplayConfig
    var onAddToFeature: (() -> Void)?
    let onTap: () -> Void

    @State private var isHovering = false

    nonisolated static func == (lhs: PRRowView, rhs: PRRowView) -> Bool {
        lhs.pull.url == rhs.pull.url
            && lhs.pull.updatedAt == rhs.pull.updatedAt
            && lhs.pull.isReadByViewer == rhs.pull.isReadByViewer
            && lhs.isSelected == rhs.isSelected
            && lhs.config == rhs.config
    }

    private var approvedByMe: Bool {
        pull.reviews.edges.contains { $0.node.author?.login == config.githubUsername }
    }

    private var isStale: Bool {
        guard let staleDate = config.staleDate else { return false }
        return pull.updatedAt < staleDate
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12), in: Capsule())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                if config.showAvatar {
                    AsyncAvatarView(url: pull.author?.avatarUrl)
                        .frame(width: Theme.avatarSize, height: Theme.avatarSize)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if config.showUnreadDot && !pull.isReadByViewer {
                            Circle()
                                .fill(Theme.unread)
                                .frame(width: Theme.unreadDotSize, height: Theme.unreadDotSize)
                        }
                        if pull.isDraft { badge("Draft", Theme.draft) }
                        if isStale { badge("Stale", Theme.stale) }
                        if pull.mergeable == "CONFLICTING" { badge("Merge conflict", Theme.failure) }
                        if pull.reviewDecision == "CHANGES_REQUESTED" { badge("Changes requested", Theme.pending) }
                        Text(pull.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                    }

                    HStack(spacing: 0) {
                        Text(pull.repository.name)
                            .fontWeight(.medium)
                        Text("  ")
                        Text(pull.author?.login ?? "ghost")
                            .foregroundStyle(.tertiary)
                        Text("  ")
                        Text(pull.createdAt.getElapsedInterval())
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 4)

                        HStack(spacing: 8) {
                            if config.showApprovals && pull.reviews.totalCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: approvedByMe ? "checkmark.circle.fill" : "checkmark.circle")
                                        .foregroundStyle(approvedByMe ? Theme.success : Theme.neutral)
                                    Text("\(pull.reviews.totalCount)")
                                }
                            }

                            if config.showLinesChanged, let add = pull.additions, let del = pull.deletions {
                                HStack(spacing: 2) {
                                    Text("+\(add)")
                                        .foregroundStyle(Theme.success)
                                    Text("-\(del)")
                                        .foregroundStyle(Theme.failure)
                                }
                            }

                            if let commits = pull.commits {
                                CIDotsView(commits: commits)
                            }
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if isHovering, let onAddToFeature {
                    CircleIconButton(icon: "puzzlepiece.extension", size: 9, frameSize: 18, help: "Add to feature") {
                        onAddToFeature()
                    }
                }

                if !config.clickOpensLink {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isSelected ? 90 : 0))
                }
            }
            .padding(.vertical, Theme.rowPaddingV)
            .padding(.horizontal, Theme.rowPaddingH)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? Theme.selectedBackground : isHovering ? Theme.hoverBackground : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct PRDetailView: View {
    let pull: Pull

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pull.title)
                .font(.system(size: 12.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)

            if !pull.labels.nodes.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(pull.labels.nodes, id: \.name) { label in
                        Text(label.name)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(ColorCache.color(hex: label.color).opacity(Theme.labelBackgroundOpacity))
                            .foregroundStyle(ColorCache.color(hex: label.color))
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                if let commits = pull.commits {
                    CIDetailView(commits: commits)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                PRInfoColumn(pull: pull)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(pull.url)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Open in Browser")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.contentPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.groupedBackground)
        )
    }
}

private struct PRInfoColumn: View {
    let pull: Pull

    private var reviewers: [String] {
        pull.reviews.edges.compactMap { $0.node.author?.login }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CopyableRow(icon: "arrow.triangle.branch", label: pull.headRefName, value: pull.headRefName)
            CopyableRow(icon: "link", label: "\(pull.repository.name) #\(pull.number)", value: pull.url.absoluteString)
            InfoRow(icon: "clock", label: "Updated \(pull.updatedAt.getElapsedInterval())")

            if let add = pull.additions, let del = pull.deletions {
                HStack(spacing: 4) {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Text("+\(add)")
                        .foregroundStyle(Theme.success)
                    Text("-\(del)")
                        .foregroundStyle(Theme.failure)
                }
                .font(.system(size: 10.5))
            }

            if !reviewers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .frame(width: 12)
                        Text("Approved")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10.5))

                    ForEach(reviewers, id: \.self) { reviewer in
                        Text(reviewer)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                    }
                }
            }

            if pull.isDraft {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.draft)
                        .frame(width: 6, height: 6)
                        .frame(width: 12)
                    Text("Draft PR")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.cardBackground)
        )
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct CopyableRow: View {
    let icon: String
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(copied ? Theme.success : Color.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
    }
}

struct CICheck: Identifiable {
    let name: String
    let status: String
    let url: URL?
    let index: Int

    var id: String { "\(name)-\(status)-\(index)" }

    nonisolated(unsafe) private static var cache: [String: [CICheck]] = [:]

    static func from(commits: CommitsNodes) -> [CICheck] {
        let key = commits.nodes.first?.commit.checkSuites?.nodes.first?.checkRuns.nodes.first?.name
            ?? commits.nodes.first?.commit.statusCheckRollup?.state
            ?? "empty"
        if let cached = cache[key] { return cached }

        var result: [CICheck] = []
        if let suites = commits.nodes.first?.commit.checkSuites {
            for suite in suites.nodes {
                for check in suite.checkRuns.nodes {
                    result.append(CICheck(name: check.name, status: check.conclusion ?? "PENDING", url: check.detailsUrl, index: result.count))
                }
            }
        } else if let rollup = commits.nodes.first?.commit.statusCheckRollup {
            for node in rollup.contexts.nodes {
                let name = node.name ?? node.context ?? "Check"
                let status = node.conclusion ?? node.state ?? "PENDING"
                let url = node.detailsUrl ?? (node.targetUrl.flatMap { URL(string: $0) })
                result.append(CICheck(name: name, status: status, url: url, index: result.count))
            }
        }

        cache[key] = result
        return result
    }

    static func clearCache() { cache.removeAll() }
}

struct CIDetailView: View {
    let checks: [CICheck]

    init(commits: CommitsNodes) {
        self.checks = CICheck.from(commits: commits)
    }

    var body: some View {
        if !checks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHECKS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                ForEach(checks) { check in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ciStatusColor(check.status))
                            .frame(width: Theme.ciDotSize, height: Theme.ciDotSize)
                        Text(check.name)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                        Spacer()
                        if let url = check.url {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.cardBackground)
            )
        }
    }
}

private func ciStatusColor(_ status: String) -> Color {
    switch status {
    case "SUCCESS": Theme.success
    case "FAILURE": Theme.failure
    case "PENDING", "ACTION_REQUIRED": Theme.pending
    default: Theme.neutral
    }
}

struct CIDotsView: View {
    let checks: [CICheck]

    init(commits: CommitsNodes) {
        self.checks = CICheck.from(commits: commits)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(checks) { check in
                Circle()
                    .fill(ciStatusColor(check.status))
                    .frame(width: Theme.ciDotInlineSize, height: Theme.ciDotInlineSize)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    struct CacheData {
        var positions: [CGPoint] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> CacheData { CacheData() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        cache = computeLayout(proposal: proposal, subviews: subviews)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> CacheData {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return CacheData(positions: positions, size: CGSize(width: maxX, height: y + rowHeight))
    }
}

struct AsyncAvatarView: View, Equatable {
    let url: URL?
    @State private var image: NSImage?

    nonisolated static func == (lhs: AsyncAvatarView, rhs: AsyncAvatarView) -> Bool {
        lhs.url == rhs.url
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
        }
        .clipShape(Circle())
        .task(id: url) {
            guard let url else { return }
            image = await NSImage.loadImage(from: url)
        }
    }
}

enum ColorCache {
    nonisolated(unsafe) private static var cache: [String: Color] = [:]

    static func color(hex: String) -> Color {
        if let cached = cache[hex] { return cached }
        var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.remove(at: cString.startIndex) }
        guard cString.count == 6 else { return Theme.neutral }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        let color = Color(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
        cache[hex] = color
        return color
    }
}

