import SwiftUI

struct TimelineSearchBar: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let onNavigate: () -> Void
    var isUnderstanding = false
    var understood = false
    var searchMessage: String? = nil
    var naturalLanguageEnabled = false
    var body: some View {
        HStack(spacing: Spacing.xxl) {
            PullRequestGlyph().fill(Palette.accent, style: FillStyle(eoFill: true)).frame(width: Size.glyph, height: Size.glyph)
                .frame(width: Size.glyphTile, height: Size.glyphTile).background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.tile))
                .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Palette.accent.opacity(Opacity.outline)))
                .accessibilityHidden(true)
            TimelineQueryField(query: $query, focus: focus, onNavigate: onNavigate, naturalLanguageEnabled: naturalLanguageEnabled).frame(height: Size.field)
            if isUnderstanding { ProgressView().controlSize(.small).frame(width: Size.statusIcon).help("Understanding your search…").accessibilityLabel("Understanding your search") }
            else if let searchMessage {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.textSecondary).frame(width: Size.statusIcon)
                    .help(searchMessage).accessibilityLabel(searchMessage)
            } else if understood {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent).frame(width: Size.statusIcon)
                    .help("Search understood with Apple Intelligence").accessibilityLabel("Search understood with Apple Intelligence")
            }
            Button("/") { focus.wrappedValue = true }
                .buttonStyle(.key).help("Focus filter (/)").accessibilityLabel("Focus filter")
        }.padding(.horizontal, Spacing.panel).padding(.vertical, Spacing.xxxl)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
    }
}
