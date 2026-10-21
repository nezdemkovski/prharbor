import SwiftUI

extension Freshness {
    /// Bars, dots and hatching.
    var fill: Color {
        switch self {
        case .fresh: Palette.freshFill
        case .aging: Palette.agingFill
        case .stale: Palette.staleFill
        case .rotting: Palette.rottingFill
        }
    }
    /// Text in this freshness color.
    var label: Color {
        switch self {
        case .fresh: Palette.freshLabel
        case .aging: Palette.agingLabel
        case .stale: Palette.staleLabel
        case .rotting: Palette.rottingLabel
        }
    }
}
