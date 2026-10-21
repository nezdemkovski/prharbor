import Defaults
import SwiftUI

/// Content equality excludes action closures, which access the panel's live
/// State/Defaults storage. Scrolling retains overlapping row render trees.
struct TimelinePresentedRow: View, Equatable {
    let row: TimelinePresentation.Row
    let scale: TimelineScale
    let now: Date
    let selection: String?
    let showOwner: Bool
    let stackCollapsed: Bool
    let height: CGFloat?
    let select: (String) -> Void
    let toggleRepo: (String) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.scale == rhs.scale && lhs.now == rhs.now
            && lhs.selection == rhs.selection && lhs.showOwner == rhs.showOwner
            && lhs.stackCollapsed == rhs.stackCollapsed && lhs.height == rhs.height
    }
    var body: some View {
        Group {
            switch row {
            case .repository(let name, let items, let collapsed):
                TimelineRepositoryHeader(
                    name: name, items: items, scale: scale,
                    collapsed: collapsed, showOwner: showOwner
                ) { toggleRepo(name) }
            case .pull(let item):
                TimelineRow(item: item, scale: scale, now: now, selected: selection == item.id) { select(item.id) }
            case .stack(let group, let items):
                TimelineStackRows(
                    group: group, items: items, scale: scale, now: now, selection: selection,
                    isCollapsed: stackCollapsed,
                    select: select, toggle: { toggleRepo("stack:" + group.id) })
            }
        }.frame(height: height, alignment: .top)
    }
}
