import SwiftUI

/// The checks fact in the details card: the first failing check with its log, or the overall state.
struct TimelineChecksSummary: View {
    let item: TimelineItem

    var body: some View {
        let failures = item.checks.filter { ciStatusKind($0.status) == .failure }
        if let check = failures.first {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "xmark.circle").foregroundStyle(Palette.failure)
                Text(check.name + (failures.count > 1 ? " +\(failures.count - 1)" : "")).lineLimit(1).foregroundStyle(Palette.failure)
                if let url = check.url { Link("Open log ↗", destination: url).foregroundStyle(Palette.textPrimary) }
            }
        } else if item.ci == .failure {
            SwiftUI.Label("Checks failed", systemImage: "xmark.circle").foregroundStyle(Palette.failure)
                .help("A failing check is outside the loaded details. Open GitHub for all checks.")
        } else if item.ci == .pending {
            SwiftUI.Label("Checks running", systemImage: "clock").foregroundStyle(Palette.warning)
        } else if item.ci == .success {
            SwiftUI.Label("Checks passed", systemImage: "checkmark.circle").foregroundStyle(Palette.success)
        } else {
            SwiftUI.Label("Check status unknown", systemImage: "questionmark.circle").foregroundStyle(Palette.textSecondary)
        }
    }
}
