import SwiftUI

/// What the row area shows when no row is visible: progress, an all-clear, or a way out of
/// filters that hide everything.
struct TimelineEmptyState: View {
    let isLoading: Bool
    let isSearching: Bool
    let isFiltered: Bool
    /// Why a natural-language search matched nothing, when it was one.
    let searchMessage: String?
    let clearFilters: () -> Void

    var body: some View {
        if isLoading {
            ProgressView("Fetching pull requests…")
        } else if isSearching {
            ProgressView("Searching…")
        } else if !isFiltered {
            ContentUnavailableView {
                Label("All Clear", systemImage: "checkmark.circle")
            } description: {
                Text("No open pull requests.").foregroundStyle(Palette.textSecondary)
            }
        } else {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(searchMessage ?? "No pull request fits these filters.").foregroundStyle(Palette.textSecondary)
            } actions: {
                Button("Clear Filters", action: clearFilters)
            }
        }
    }
}
