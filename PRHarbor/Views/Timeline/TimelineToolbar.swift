import SwiftUI
import Defaults

struct TimelineSegment<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, title: String, count: Int?)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.value } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                        if let count = option.count { Text("\(count)").fontWeight(.medium).foregroundStyle(TimelineStyle.faint) }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selection == option.value ? TimelineStyle.text : TimelineStyle.muted)
                    .padding(.horizontal, 10).padding(.vertical, 4).frame(height: 24)
                    .background {
                        if selection == option.value {
                            RoundedRectangle(cornerRadius: 7).fill(TimelineStyle.panel)
                                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(TimelineStyle.strong, lineWidth: 1))
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(option.title + (option.count.map { ", \($0) pull requests" } ?? ""))
                    .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
            }
        }
        .padding(3).background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TimelineStyle.line))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
        .fixedSize()
    }
}

struct TimelineSearchBar: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let onNavigate: () -> Void
    var isUnderstanding = false
    var understood = false
    var searchMessage: String? = nil
    var naturalLanguageEnabled = false
    var body: some View {
        HStack(spacing: 14) {
            PullRequestGlyph().fill(TimelineStyle.accent, style: FillStyle(eoFill: true)).frame(width: 18, height: 18)
                .frame(width: 38, height: 38).background(TimelineStyle.accentSoft, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(TimelineStyle.accent.opacity(0.2)))
                .accessibilityHidden(true)
            TimelineQueryField(query: $query, focus: focus, onNavigate: onNavigate, naturalLanguageEnabled: naturalLanguageEnabled).frame(height: 28)
            if isUnderstanding { ProgressView().controlSize(.small).frame(width: 20).help("Understanding your search…").accessibilityLabel("Understanding your search") }
            else if let searchMessage {
                Image(systemName: "exclamationmark.circle").foregroundStyle(TimelineStyle.muted).frame(width: 20)
                    .help(searchMessage).accessibilityLabel(searchMessage)
            } else if understood {
                Image(systemName: "sparkles").foregroundStyle(TimelineStyle.accent).frame(width: 20)
                    .help("Search understood with Apple Intelligence").accessibilityLabel("Search understood with Apple Intelligence")
            }
            Button { focus.wrappedValue = true } label: {
                Text("/").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                    .foregroundStyle(TimelineStyle.accent).background(TimelineStyle.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).help("Focus filter (/)").accessibilityLabel("Focus filter")
        }.padding(.horizontal, 18).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(TimelineStyle.line).frame(height: 1) }
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
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.cell?.isScrollable = true; field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: "Filter… try “mine stale” or “noona-api >2w”", attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(TimelineStyle.faint)])
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Filter pull requests")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = NSAttributedString(string: naturalLanguageEnabled ? "Search… try “my PRs older than two weeks”" : "Filter… try “mine stale” or “noona-api >2w”", attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(TimelineStyle.faint)])
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
            let styled = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(TimelineStyle.text), .kern: -0.18])
            let tokens = ["mine", "my", "review", "reviews", "reviewing", "draft", "snoozed", "blocked", "fresh", "aging", "stale", "rotting", "smelly", "bot", "bots", "failing", "red", "approved", "conflict", "stack", "stacks", "team", "decide", "dead", "unreviewed"]
            for match in Self.words?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? [] {
                let word = (text as NSString).substring(with: match.range)
                if tokens.contains(word.lowercased()) || word.hasPrefix(">") || word.hasPrefix("<") || word.hasPrefix("idle:") {
                    styled.addAttributes([.foregroundColor: NSColor(TimelineStyle.accent), .backgroundColor: NSColor(TimelineStyle.accentSoft)], range: match.range)
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
                editor.insertionPointColor = NSColor(TimelineStyle.accent)
                editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(TimelineStyle.text)]
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
    @ObservedObject var store: PullRequestStore
    var isPreview = false
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    private var created: Binding<Bool> {
        Binding(get: { sortOrder == .createdNewest || sortOrder == .createdOldest }, set: { sortOrder = $0 ? .createdNewest : .updatedNewest })
    }
    var body: some View {
        HStack(spacing: 10) {
            TimelineSegment(label: "Pull requests", selection: $tab, options: TimelineTab.allCases.map { tab in
                (tab, tab.rawValue, items.filter { tab == .all || (tab == .mine ? $0.isMine : !$0.isMine) }.count)
            })
            HStack(spacing: 6) {
                Circle().fill(syncColor).frame(width: 6, height: 6)
                Text(isPreview ? "Mock data" : syncLabel).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(syncColor)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(isPreview ? TimelineStyle.track : syncColor.opacity(0.12), in: Capsule())
            .help("Refresh from GitHub (⌘R)").onTapGesture { if !isPreview { store.refresh() } }
            Spacer(minLength: 0)
            TimelineSegment(label: "Sort", selection: created, options: [(false, "Updated", nil), (true, "Created", nil)])
            TimelineSegment(label: "Timeline range", selection: $range, options: [(14, "2W", nil), (30, "1M", nil), (90, "3M", nil), (182, "6M", nil)])
            Button(action: onSettings) { Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 28, height: 28).foregroundStyle(TimelineStyle.muted) }
                .buttonStyle(.plain).help("Settings (⌘,)").accessibilityLabel("Settings").keyboardShortcut(",")
                .contextMenu { Button("Refresh") { store.refresh() }; Button("About PR Harbor", action: onAbout); Button("Quit PR Harbor", action: onQuit) }
        }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
        .background {
            Button("Refresh") { store.refresh() }.keyboardShortcut("r").hidden().accessibilityHidden(true)
        }
    }
    private var syncColor: Color {
        if isPreview || store.isLoading { return TimelineStyle.muted }
        if store.error != nil { return Theme.failure }
        return Freshness.fresh.color
    }
    private var syncLabel: String {
        if store.isLoading { return "Syncing…" }
        if store.error != nil { return "Sync failed" }
        guard let date = store.lastSyncedAt else { return "Live" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return (store.isShowingCache ? (store.hasIncompleteData ? "Cached · partial · " : "Cached · ") : "Live · ") + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m ago" : minutes < 1440 ? "\(Int((Double(minutes) / 60).rounded()))h ago" : "\(Int((Double(minutes) / 1440).rounded()))d ago")
    }
}
