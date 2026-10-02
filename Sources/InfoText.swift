import AppKit

/// Rich text for the guide and about alerts: small section headings, a
/// label column for keys and steps, and `backtick` spans set in monospace
/// for what the user types.
final class InfoText {
    static let width: CGFloat = 380
    private static let labelColumn: CGFloat = 76
    private static let bodyFont = NSFont.systemFont(ofSize: 13)
    private static let keysFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private let text = NSMutableAttributedString()

    func heading(_ title: String) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = text.length == 0 ? 0 : 12
        style.paragraphSpacing = 4
        append(title.uppercased() + "\n", [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.4,
            .paragraphStyle: style,
        ])
    }

    /// One entry with a label column.  Wrapped lines, and lines split with
    /// "\n" in `detail`, stay aligned under the detail.
    func row(_ label: String, _ detail: String) {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: Self.labelColumn)]
        style.headIndent = Self.labelColumn
        style.paragraphSpacing = 3
        append(label, [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                       .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        append("\t", [.font: Self.bodyFont, .paragraphStyle: style])
        inline(detail.replacingOccurrences(of: "\n", with: "\u{2028}") + "\n", style: style)
    }

    func paragraph(_ body: String, secondary: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 3
        inline(body + "\n", style: style, color: secondary ? .secondaryLabelColor : .labelColor)
    }

    func link(_ title: String, _ url: URL) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 10
        append(title + "\n", [.font: Self.bodyFont, .link: url, .paragraphStyle: style])
    }

    /// A non-editable, selectable text view sized to its content, for
    /// `NSAlert.accessoryView`.
    func view() -> NSView {
        let content = text.copy() as! NSAttributedString
        let trimmed = content.string.hasSuffix("\n")
            ? content.attributedSubstring(from: NSRange(location: 0, length: content.length - 1))
            : content
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 10))
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        view.textStorage?.setAttributedString(trimmed)
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            view.frame.size.height = ceil(layout.usedRect(for: container).height)
        }
        return view
    }

    private func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
        text.append(NSAttributedString(string: string, attributes: attributes))
    }

    private func inline(_ string: String, style: NSParagraphStyle, color: NSColor = .labelColor) {
        for (index, part) in string.components(separatedBy: "`").enumerated() {
            append(part, [.font: index % 2 == 1 ? Self.keysFont : Self.bodyFont,
                          .foregroundColor: color, .paragraphStyle: style])
        }
    }
}
