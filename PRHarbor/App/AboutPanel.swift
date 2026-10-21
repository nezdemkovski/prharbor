import AppKit

/// The standard About window, with the project's links as credits.
@MainActor func showAboutPanel() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: Typography.footnote), .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph
    ]
    let credits = NSMutableAttributedString(string: "GitHub pull requests in your menu bar.\nby Yuri Nezdemkovski\n\n", attributes: base)
    for (index, (title, address)) in [
        ("GitHub", "https://github.com/nezdemkovski/prharbor"), ("nezdemkovski.com", "https://nezdemkovski.com")
    ].enumerated() {
        if index > 0 { credits.append(NSAttributedString(string: "  ·  ", attributes: base)) }
        var link = base
        link[.link] = URL(string: address)
        credits.append(NSAttributedString(string: title, attributes: link))
    }
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}
