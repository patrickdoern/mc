import AppKit
import MCCore

enum MarkupKind {
    case markdown, html

    static func kind(forFile name: String) -> MarkupKind? {
        switch name.lowercased().split(separator: ".").last.map(String.init) {
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm", "xhtml": return .html
        default: return nil
        }
    }
}

enum MarkupRenderer {
    static let maximumLength = 2_000_000
    private static let bodySize: CGFloat = 14

    static func render(_ source: String, kind: MarkupKind) -> NSAttributedString? {
        guard source.utf16.count <= maximumLength else { return nil }
        switch kind {
        case .markdown: return renderMarkdown(source)
        case .html: return renderHTML(source)
        }
    }

    private static func renderMarkdown(_ source: String) -> NSAttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard let parsed = try? AttributedString(markdown: source, options: options) else { return nil }
        let output = NSMutableAttributedString()
        var previous: Block?
        var previousStyle = NSParagraphStyle.default
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = Block(components)
            let style = paragraphStyle(for: block, gapBefore: block.identity != previous?.identity && Self.endsGroup(previous, before: block))
            if block.identity != previous?.identity {
                if let previous {
                    let inSameRow = block.rowIdentity != nil && block.rowIdentity == previous.rowIdentity
                    let separatorStyle = previousStyle
                    output.append(NSAttributedString(string: inSameRow ? "  │  " : "\n", attributes: [.paragraphStyle: separatorStyle, .font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: Theme.editorText]))
                }
                if let prefix = block.prefix {
                    output.append(NSAttributedString(string: prefix, attributes: attributes(for: block, inline: [], link: nil, style: style)))
                }
            }
            var text = String(parsed[run.range].characters)
            if block.isCode, text.hasSuffix("\n") { text.removeLast() }
            output.append(NSAttributedString(string: text, attributes: attributes(for: block, inline: run.inlinePresentationIntent ?? [], link: run.link, style: style)))
            previous = block
            previousStyle = style
        }
        return output
    }

    private struct Block {
        var identity: Int?
        var rowIdentity: Int?
        var headerLevel: Int?
        var isCode = false
        var quoteDepth = 0
        var listDepth = 0
        var prefix: String?
        var isTableHeader = false

        init(_ components: [PresentationIntent.IntentType]) {
            identity = components.first?.identity
            var ordinal: Int?
            var ordered = false
            for (index, component) in components.enumerated() {
                switch component.kind {
                case .header(let level): headerLevel = level
                case .codeBlock: isCode = true
                case .blockQuote: quoteDepth += 1
                case .listItem(let number):
                    listDepth += 1
                    if ordinal == nil {
                        ordinal = number
                        if components.indices.contains(index + 1), case .orderedList = components[index + 1].kind { ordered = true }
                    }
                case .tableHeaderRow:
                    rowIdentity = component.identity
                    isTableHeader = true
                case .tableRow:
                    rowIdentity = component.identity
                default: break
                }
            }
            if let ordinal {
                let indent = String(repeating: "    ", count: max(listDepth - 1, 0))
                prefix = indent + (ordered ? "\(ordinal). " : (listDepth > 1 ? "◦ " : "• "))
            } else if quoteDepth > 0 {
                prefix = String(repeating: "▍ ", count: quoteDepth)
            }
        }
    }

    private static func endsGroup(_ previous: Block?, before block: Block) -> Bool {
        guard let previous else { return false }
        return (previous.listDepth > 0 && block.listDepth == 0) || previous.isCode || (previous.rowIdentity != nil && block.rowIdentity == nil)
    }

    private static func paragraphStyle(for block: Block, gapBefore: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = block.isCode || block.rowIdentity != nil ? 0 : block.listDepth > 0 ? 3 : block.headerLevel != nil ? 8 : 10
        style.paragraphSpacingBefore = block.headerLevel != nil ? 10 : gapBefore ? 10 : 0
        style.lineSpacing = block.isCode ? 0 : 2
        if block.listDepth > 0 {
            style.firstLineHeadIndent = CGFloat(max(block.listDepth - 1, 0)) * 4
            style.headIndent = CGFloat(block.listDepth) * 22
        } else if block.quoteDepth > 0 {
            style.firstLineHeadIndent = 4
            style.headIndent = 20
        }
        return style
    }

    private static func attributes(for block: Block, inline: InlinePresentationIntent, link: URL?, style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var size = bodySize
        var bold = false
        var italic = false
        var monospaced = block.isCode
        if let level = block.headerLevel {
            size = [26, 22, 19, 17, 15, 14][min(max(level, 1), 6) - 1]
            bold = true
        }
        if block.isTableHeader { bold = true }
        if inline.contains(.stronglyEmphasized) { bold = true }
        if inline.contains(.emphasized) { italic = true }
        if inline.contains(.code) { monospaced = true }
        var font: NSFont = monospaced ? NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: bold ? .bold : .regular) : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var result: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: Theme.editorText]
        if block.headerLevel != nil { result[.foregroundColor] = Theme.syntaxColor(.keyword) }
        if block.quoteDepth > 0 { result[.foregroundColor] = Theme.syntaxColor(.comment) }
        if monospaced {
            result[.backgroundColor] = Theme.editorText.withAlphaComponent(0.1)
            if inline.contains(.code) || block.isCode { result[.foregroundColor] = Theme.syntaxColor(.string) }
        }
        if inline.contains(.strikethrough) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link {
            result[.link] = link
            result[.foregroundColor] = Theme.syntaxColor(.property)
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return result
    }

    private static func renderHTML(_ source: String) -> NSAttributedString? {
        let sanitized = sanitize(source)
        guard let data = sanitized.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue]
        guard let loaded = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else { return nil }
        let full = NSRange(location: 0, length: loaded.length)
        loaded.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if loaded.attribute(.link, at: range.location, effectiveRange: nil) != nil {
                loaded.addAttribute(.foregroundColor, value: Theme.syntaxColor(.property), range: range)
                loaded.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else if (value as? NSColor).map({ contrast($0, Theme.background) < 3 }) ?? true {
                loaded.addAttribute(.foregroundColor, value: Theme.editorText, range: range)
            }
        }
        loaded.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let original = value as? NSFont else { return }
            let traits = original.fontDescriptor.symbolicTraits
            let size = max(original.pointSize * 1.15, 12)
            var font = traits.contains(.monoSpace) ? NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) : NSFont.systemFont(ofSize: size, weight: traits.contains(.bold) ? .bold : .regular)
            if traits.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            loaded.addAttribute(.font, value: font, range: range)
        }
        return loaded
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> CGFloat { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
    }

    private static func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let high = max(luminance(first), luminance(second))
        let low = min(luminance(first), luminance(second))
        return (high + 0.05) / (low + 0.05)
    }

    private static func sanitize(_ html: String) -> String {
        var result = html
        for (pattern, replacement) in [
            (#"<script\b[\s\S]*?</script\s*>"#, ""),
            (#"<(iframe|object|embed|video|audio)\b[\s\S]*?</\1\s*>"#, ""),
            (#"<link\b[^>]*>"#, ""),
            (#"<img\b[^>]*>"#, "[Bild]"),
        ] {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }
}
