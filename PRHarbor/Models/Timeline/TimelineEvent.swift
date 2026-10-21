import Foundation

nonisolated struct TimelineEvent: Identifiable, Equatable {
    let id: Int
    let date: Date
    let kind: Kind
    let person: User?
    enum Kind: String { case opened, commit, comment, approved, changes, requested }
    var label: String {
        let name = person?.login ?? "a team"
        switch kind {
        case .opened: return "Opened"
        case .commit: return "Commit pushed"
        case .comment: return "\(name) commented"
        case .approved: return "Approved by \(name)"
        case .changes: return "Changes requested by \(name)"
        case .requested: return "Review requested from \(name)"
        }
    }
}
