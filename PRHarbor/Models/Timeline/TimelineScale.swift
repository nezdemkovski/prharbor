import Foundation

nonisolated struct TimelineScale: Equatable {
    let days: Int
    var isLogarithmic: Bool { days == 182 }
    func position(age: Double) -> Double {
        let fraction = isLogarithmic ? log1p(max(0, age) / 4) / log1p(Double(days) / 4) : max(0, age) / Double(days)
        return min(1, max(0, 1 - fraction))
    }
    func age(at position: Double) -> Double {
        let p = min(1, max(0, position))
        return isLogarithmic ? 4 * expm1((1 - p) * log1p(Double(days) / 4)) : (1 - p) * Double(days)
    }
    /// The whole day nearest `age`, within the scale. A timeline selection is stored in days.
    func wholeDay(_ age: Double) -> Double {
        min(Double(days), max(0, age.rounded()))
    }
    var ticks: [Double] {
        switch days {
        case 14: [14, 10, 7, 3, 0]
        case 30: [30, 21, 14, 7, 0]
        case 90: [90, 60, 30, 14, 0]
        default: [182, 90, 30, 14, 7, 0]
        }
    }
}
