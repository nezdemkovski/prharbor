import SwiftUI
import Defaults

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

/// AppKit owns editing, selection and the caret; syntax color never replaces the editor.
struct TimelineQueryField: NSViewRepresentable {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let onNavigate: () -> Void
    var naturalLanguageEnabled = false
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: Typography.display, weight: .medium)
        field.cell?.isScrollable = true; field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: "Filter… try “mine stale” or “noona-api >2w”", attributes: [.font: NSFont.systemFont(ofSize: Typography.display, weight: .medium), .foregroundColor: NSColor(Palette.textTertiary)])
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Filter pull requests")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = NSAttributedString(string: naturalLanguageEnabled ? "Search… try “my PRs older than two weeks”" : "Filter… try “mine stale” or “noona-api >2w”", attributes: [.font: NSFont.systemFont(ofSize: Typography.display, weight: .medium), .foregroundColor: NSColor(Palette.textTertiary)])
        field.setAccessibilityLabel(naturalLanguageEnabled ? "Search pull requests" : "Filter pull requests")
        if let editor = field.currentEditor() as? NSTextView {
            if !editor.hasMarkedText(), editor.string != query { editor.string = query }
        } else if field.stringValue != query { field.stringValue = query }
        context.coordinator.highlightIfNeeded(field)
        if focus.wrappedValue, field.currentEditor() == nil, let window = field.window { window.makeFirstResponder(field) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimelineQueryField
        private var styledText: String?
        private var styledAppearance: String?
        private static let words = try? NSRegularExpression(pattern: "\\S+")
        init(_ parent: TimelineQueryField) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) {
            styledText = nil
            parent.focus.wrappedValue = true
        }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focus.wrappedValue = false }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let editor = field.currentEditor() as? NSTextView
            // Do not replace marked text while an input method is composing a word.
            guard editor?.hasMarkedText() != true else { return }
            parent.query = editor?.string ?? field.stringValue
            highlightIfNeeded(field)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch NSStringFromSelector(selector) {
            case "moveDown:", "insertNewline:": parent.onNavigate(); return true
            case "cancelOperation:": if parent.query.isEmpty { parent.onNavigate() } else { parent.query = "" }; return true
            default: return false
            }
        }
        func highlightIfNeeded(_ field: NSTextField) {
            let editor = field.currentEditor() as? NSTextView
            guard editor?.hasMarkedText() != true else { return }
            let text = editor?.string ?? field.stringValue
            let appearance = field.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue
            guard text != styledText || appearance != styledAppearance else { return }
            styledText = text; styledAppearance = appearance
            let styled = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: Typography.display, weight: .medium), .foregroundColor: NSColor(Palette.textPrimary), .kern: -0.18])
            let tokens = ["mine", "my", "review", "reviews", "reviewing", "draft", "snoozed", "blocked", "fresh", "aging", "stale", "rotting", "smelly", "bot", "bots", "failing", "red", "approved", "conflict", "stack", "stacks", "team", "decide", "dead", "unreviewed"]
            for match in Self.words?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? [] {
                let word = (text as NSString).substring(with: match.range)
                if tokens.contains(word.lowercased()) || word.hasPrefix(">") || word.hasPrefix("<") || word.hasPrefix("idle:") {
                    styled.addAttributes([.foregroundColor: NSColor(Palette.accent), .backgroundColor: NSColor(Palette.accentSoft)], range: match.range)
                }
            }
            if let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage {
                let selection = editor.selectedRanges
                if storage.string == text {
                    storage.beginEditing()
                    styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attributes, range, _ in storage.setAttributes(attributes, range: range) }
                    storage.endEditing()
                } else { storage.setAttributedString(styled) }
                editor.selectedRanges = selection.map { value in
                    let start = min(value.rangeValue.location, styled.length)
                    return NSValue(range: NSRange(location: start, length: min(value.rangeValue.length, styled.length - start)))
                }
                editor.insertionPointColor = NSColor(Palette.accent)
                editor.typingAttributes = [.font: NSFont.systemFont(ofSize: Typography.display, weight: .medium), .foregroundColor: NSColor(Palette.textPrimary)]
            } else { field.attributedStringValue = styled }
        }
    }
}

struct TimelineHeading: View {
    let items: [TimelineItem]
    let now: Date
    @Binding var tab: TimelineTab
    @Binding var range: Int
    @Binding var sortOrder: SortOrder
    let store: PullRequestStore
    var isPreview = false
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    private var created: Binding<Bool> {
        Binding(get: { sortOrder == .createdNewest || sortOrder == .createdOldest }, set: { sortOrder = $0 ? .createdNewest : .updatedNewest })
    }
    var body: some View {
        HStack(spacing: Spacing.l) {
            SegmentedControl(label: "Pull requests", selection: $tab, options: TimelineTab.allCases.map { tab in
                (tab, tab.rawValue, items.filter { tab == .all || (tab == .mine ? $0.isMine : !$0.isMine) }.count)
            })
            Button { if !isPreview { store.refresh() } } label: {
                HStack(spacing: Spacing.s) {
                    Circle().fill(syncColor).frame(width: Size.statusDot, height: Size.statusDot)
                    Text(isPreview ? "Mock data" : syncLabel)
                }
            }
            .buttonStyle(.badge(syncColor, background: isPreview ? Palette.track : syncColor.opacity(Opacity.badge)))
            .help("Refresh from GitHub (⌘R)")
            Spacer(minLength: 0)
            SegmentedControl(label: "Sort", selection: created, options: [(false, "Updated", nil), (true, "Created", nil)])
            SegmentedControl(label: "Timeline range", selection: $range, options: [(14, "2W", nil), (30, "1M", nil), (90, "3M", nil), (182, "6M", nil)])
            Button(action: onSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.icon(size: Size.iconButton, symbolSize: Typography.iconLarge)).help("Settings (⌘,)").accessibilityLabel("Settings").keyboardShortcut(",")
                .contextMenu { Button("Refresh") { store.refresh() }; Button("About PR Harbor", action: onAbout); Button("Quit PR Harbor", action: onQuit) }
        }.padding(.horizontal, Spacing.panel).padding(.top, Spacing.xxxl).padding(.bottom, Spacing.s)
        .background {
            Button("Refresh") { store.refresh() }.keyboardShortcut("r").hidden().accessibilityHidden(true)
        }
    }
    private var syncColor: Color {
        if isPreview || store.isLoading { return Palette.textSecondary }
        if store.error != nil { return Palette.failure }
        return Freshness.fresh.label
    }
    private var syncLabel: String {
        if store.isLoading { return "Syncing…" }
        if store.error != nil { return "Sync failed" }
        guard let date = store.lastSyncedAt else { return "Live" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return (store.isShowingCache ? (store.hasIncompleteData ? "Cached · partial · " : "Cached · ") : "Live · ") + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m ago" : minutes < 1440 ? "\(Int((Double(minutes) / 60).rounded()))h ago" : "\(Int((Double(minutes) / 1440).rounded()))d ago")
    }
}
