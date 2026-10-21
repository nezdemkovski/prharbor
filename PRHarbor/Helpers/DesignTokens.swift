import AppKit
import SwiftUI

// Design tokens: every color, type size, spacing, radius, fixed size and opacity the panel
// uses. Views refer to these names instead of literals. docs/design-tokens.md lists the
// contrast of each color pair; Scripts/design-contrast.py recomputes it.

/// Colors with a light and a dark value. Text colors meet WCAG 2.2 AA (4.5:1) on every
/// surface they appear on; fills and borders that identify state meet 3:1.
nonisolated enum Palette {
    static func color(_ light: Int, _ dark: Int? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? (dark ?? light) : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }

    // Surfaces
    static let panel = color(0xffffff, 0x1a1b1f)
    static let track = color(0xf8f9fa, 0x1f2125)
    static let hover = color(0xf6f7f9, 0x222428)
    static let active = color(0xe3e6eb, 0x33363c)
    static let accentSoft = color(0xe9f1fe, 0x1d2a40)

    // Lines. Decorative: every bordered control also has a label.
    static let line = color(0xeef0f3, 0x26282d)
    static let strong = color(0xe3e6eb, 0x2f3237)

    // Text: primary ≥ 13:1, secondary ≥ 5.4:1, tertiary ≥ 4.6:1 on panel, track and hover.
    static let ink = 0x16181c
    static let textPrimary = color(ink, 0xeceef1)
    static let textSecondary = color(0x595f68, 0x9399a1)
    static let textTertiary = color(0x677181, 0x878c96)

    // Accent: text and icons (≥ 4.5:1 on panel and accentSoft), and button fills under
    // white labels (≥ 4.5:1).
    static let accent = color(0x0c62f4, 0x5b9cff)
    static let accentFill = color(0x0c62f4, 0x0d6dff)
    static let onAccent = Color.white

    // Freshness. Fills (bars, dots, hatching) ≥ 3:1; labels ≥ 4.5:1 on the panel and on
    // their own 15% tint.
    static let freshFill = color(0x1fa454, 0x22b25b)
    static let agingFill = color(0xb48905, 0xd4a106)
    static let staleFill = color(0xe36e0f, 0xf07a1a)
    static let rottingFill = color(0xe5484d, 0xe5484d)
    static let freshLabel = color(0x17773d, 0x22b25b)
    static let agingLabel = color(0x846404, 0xd4a106)
    static let staleLabel = color(0xa5500b, 0xf07a1a)
    static let rottingLabel = color(0xc81c22, 0xea6c70)

    // Status, drawn from the same scale.
    static let success = freshLabel
    static let warning = agingLabel
    static let failure = rottingLabel

    /// Shadows and the knockout used to cut stack connectors.
    static let shadow = Color.black
}

/// Type sizes by role. Every size the panel uses is one of these.
nonisolated enum Typography {
    static let display: CGFloat = 18      // search field
    static let iconLarge: CGFloat = 17    // toolbar settings icon
    static let title: CGFloat = 16        // onboarding title
    static let icon: CGFloat = 15         // detail card tools
    static let headline: CGFloat = 13.5   // detail card title
    static let body: CGFloat = 13         // row titles, empty states
    static let callout: CGFloat = 12      // segments, repository headers, summaries
    static let subheadline: CGFloat = 11.5 // row subtitles, detail facts, badges
    static let footnote: CGFloat = 11     // axis labels, captions, branch names
    static let caption: CGFloat = 10.5    // timeline chips
    static let caption2: CGFloat = 10     // annotations inside tracks
    static let micro: CGFloat = 9.5       // disclosure chevrons, stack positions
    static let nano: CGFloat = 8          // event cluster counts, miniature initials
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

/// Spacing scale. Panel content is inset by `panel` on both sides.
nonisolated enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 3
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let xxxl: CGFloat = 16
    static let panel: CGFloat = 18
    static let section: CGFloat = 20
    static let roomy: CGFloat = 30
    static let wide: CGFloat = 40
}

/// Corner radii. Nested shapes subtract their inset: a segment (9) padded by 3 holds a
/// selection of 6.
nonisolated enum Radius {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let control: CGFloat = 9
    static let l: CGFloat = 10
    static let tile: CGFloat = 11
    static let xl: CGFloat = 12
    static let card: CGFloat = 14
}

/// Fixed sizes of icons, buttons, avatars and markers.
nonisolated enum Size {
    static let glyph: CGFloat = 18          // menu bar and search field pull request glyph
    static let glyphTile: CGFloat = 38      // tile behind the search glyph
    static let onboardingGlyph: CGFloat = 36
    static let button: CGFloat = 30         // primary action and "/" key heights
    static let iconButton: CGFloat = 28     // toolbar and detail tool buttons
    static let field: CGFloat = 28          // search field height
    static let control: CGFloat = 24        // segment height
    static let chip: CGFloat = 22           // stack summary chips, branch icon
    static let statusIcon: CGFloat = 20     // search status and onboarding feature icons
    static let smallButton: CGFloat = 18    // copy branch button
    static let handle: CGFloat = 18         // freshness threshold handles
    static let positionBadge: CGFloat = 16  // stack layer number
    static let disclosure: CGFloat = 12     // repository chevron width
    static let avatar: CGFloat = 30
    static let avatarSmall: CGFloat = 20
    static let eventAvatar: CGFloat = 16
    static let detailDot: CGFloat = 8
    static let dot: CGFloat = 7
    static let statusDot: CGFloat = 6
    static let hairline: CGFloat = 1
    static let eventTick = CGSize(width: 1.5, height: 12)
}

/// Heights and widths of specific panel regions.
nonisolated enum Layout {
    static let axisHeight: CGFloat = 30
    static let trackHeight: CGFloat = 34
    static let historyTrackHeight: CGFloat = 22
    static let detailLineHeight: CGFloat = 18
    static let stackFooterHeight: CGFloat = 26
    static let stackRailWidth: CGFloat = 42
    static let briefHeaderHeight: CGFloat = 36
    static let briefRowHeight: CGFloat = 74
    static let briefEmptyHeight: CGFloat = 52
    static let briefFooterHeight: CGFloat = 44
    static let briefActionWidth: CGFloat = 108
    static let freshnessScaleHeight: CGFloat = 68
    static let freshnessSampleHeight: CGFloat = 18
    static let freshnessSampleTitleWidth: CGFloat = 170
    static let freshnessSampleValueWidth: CGFloat = 92
    static let settingsSidebarWidth: CGFloat = 220
    static let settingsMinSize = CGSize(width: 720, height: 460)
    static let settingsDefaultSize = CGSize(width: 800, height: 560)
    static let branchMinWidth: CGFloat = 90
    static let branchMaxWidth: CGFloat = 160
}

/// Opacities by role, applied to the color they tint.
nonisolated enum Opacity {
    static let tintFill = 0.15        // freshness tint behind quiet time
    static let tintStroke = 0.45      // outline of a tinted region
    static let hatching = 0.45        // diagonal hatching inside a tint
    static let quietBar = 0.6         // quiet-time bar in repository headers
    static let todayLine = 0.75       // the "Today" rule
    static let weekendShade = 0.7     // weekend columns on the axis
    static let brushFill = 0.09       // selected time range
    static let brushEdge = 0.55       // edges of the selected time range
    static let eventTick = 0.38       // commit and own-comment ticks
    static let rowSelected = 0.55     // selected row highlight
    static let rowHover = 0.7         // hovered row highlight
    static let badge = 0.12           // tinted badge backgrounds
    static let deemphasized = 0.7     // secondary marks next to text
    static let decorativeGlyph = 0.5  // onboarding illustration
    static let outline = 0.2          // hairline highlights and outlines
    static let shadowSoft = 0.08      // segment selection shadow
    static let shadow = 0.2           // button shadow
    static let shadowStrong = 0.25    // handles
}

/// Panel geometry shared by views and layout calculations.
nonisolated enum TimelineMetrics {
    static let panelWidth: CGFloat = 780
    static let labelWidth: CGFloat = 270
    static let inset: CGFloat = Spacing.panel
    static let trackWidth = panelWidth - 2 * inset - labelWidth
    static let maxRowAreaHeight: CGFloat = 456
    /// Keeps the panel from collapsing while loading or showing only a few pull requests.
    static let minRowAreaHeight: CGFloat = 260
}
