import Foundation

/// What the panel suggests doing next with a pull request, in priority order of `TimelineItem.nextAction`.
nonisolated enum NextAction: Hashable, Sendable {
    case triage
    case review
    case reviveOrClose
    case rebase
    case fixCI
    case addressFeedback
    /// The pull request waits for the base layer of its stack with this number.
    case goToBase(Int)
    case continueDraft
    case merge
    case askForReview
    case nudgeReviewers
    case open

    /// Describes the suggestion, as in the morning overview.
    var title: String {
        switch self {
        case .triage: "Triage"
        case .review: "Review"
        case .reviveOrClose: "Revive or close"
        case .rebase: "Rebase"
        case .fixCI: "Fix CI"
        case .addressFeedback: "Address feedback"
        case .goToBase(let number): "Go to #\(number)"
        case .continueDraft: "Continue draft"
        case .merge: "Merge on GitHub"
        case .askForReview: "Ask for review"
        case .nudgeReviewers: "Nudge reviewers"
        case .open: "Open on GitHub"
        }
    }

    /// The label of the primary button in the details card.
    func buttonTitle(isMine: Bool) -> String {
        switch self {
        case .merge: "Merge"
        case .askForReview: "Request review"
        case .nudgeReviewers: "Nudge"
        case .continueDraft: "Mark ready"
        case .open: isMine ? "In review" : "Open"
        default: title
        }
    }
}
