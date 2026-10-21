import SwiftUI

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
