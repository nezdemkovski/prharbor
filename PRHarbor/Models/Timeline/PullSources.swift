import Foundation

nonisolated struct PullSources: OptionSet, Hashable, Sendable {
    let rawValue: UInt8
    static let assigned = PullSources(rawValue: 1 << 0)
    static let created = PullSources(rawValue: 1 << 1)
    static let requested = PullSources(rawValue: 1 << 2)
    static let all: PullSources = [.assigned, .created, .requested]
}
