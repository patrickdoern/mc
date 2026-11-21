import AppKit
import MCCore

struct Palette {
    let background: NSColor
    let text: NSColor
    let directory: NSColor
    let marked: NSColor
    let border: NSColor
    let cursor: NSColor
    let cursorText: NSColor
    let inactiveCursor: NSColor
    let barBackground: NSColor
    let barNumber: NSColor
    let barLabel: NSColor
    let barLabelBackground: NSColor
    let commandBackground: NSColor
    let commandText: NSColor
    let editorText: NSColor
    let editorSelection: NSColor

    static let classic = Palette(
        background: NSColor(red: 0.0, green: 0.0, blue: 0.62, alpha: 1),
        text: NSColor(red: 0.45, green: 0.95, blue: 0.95, alpha: 1),
        directory: .white,
        marked: NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1),
        border: NSColor(red: 0.75, green: 0.75, blue: 0.95, alpha: 1),
        cursor: NSColor(red: 0.0, green: 0.75, blue: 0.75, alpha: 1),
        cursorText: .black,
        inactiveCursor: NSColor(red: 0.25, green: 0.25, blue: 0.55, alpha: 1),
        barBackground: .black,
        barNumber: .white,
        barLabel: .black,
        barLabelBackground: NSColor(red: 0.0, green: 0.75, blue: 0.75, alpha: 1),
        commandBackground: .black,
        commandText: NSColor(white: 0.85, alpha: 1),
        editorText: NSColor(white: 0.9, alpha: 1),
        editorSelection: NSColor(red: 0.0, green: 0.6, blue: 0.6, alpha: 1)
    )

    static let dark = Palette(
        background: NSColor(white: 0.1, alpha: 1),
        text: NSColor(white: 0.82, alpha: 1),
        directory: .white,
        marked: NSColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1),
        border: NSColor(white: 0.45, alpha: 1),
        cursor: NSColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1),
        cursorText: .white,
        inactiveCursor: NSColor(white: 0.25, alpha: 1),
        barBackground: .black,
        barNumber: .white,
        barLabel: .white,
        barLabelBackground: NSColor(white: 0.3, alpha: 1),
        commandBackground: .black,
        commandText: NSColor(white: 0.85, alpha: 1),
        editorText: NSColor(white: 0.88, alpha: 1),
        editorSelection: NSColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1)
    )

    static let light = Palette(
        background: .white,
        text: NSColor(white: 0.12, alpha: 1),
        directory: .black,
        marked: NSColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1),
        border: NSColor(white: 0.55, alpha: 1),
        cursor: NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
        cursorText: .white,
        inactiveCursor: NSColor(white: 0.85, alpha: 1),
        barBackground: NSColor(white: 0.92, alpha: 1),
        barNumber: .black,
        barLabel: .black,
        barLabelBackground: NSColor(white: 0.8, alpha: 1),
        commandBackground: NSColor(white: 0.95, alpha: 1),
        commandText: .black,
        editorText: NSColor(white: 0.1, alpha: 1),
        editorSelection: NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1)
    )

    static let all: [(name: String, palette: Palette)] = [(localized("Norton Blau"), classic), (localized("Dunkel"), dark), (localized("Hell"), light)]
}

enum Theme {
    static let didChange = Notification.Name("ThemeDidChange")

    static var palette = Palette.all[min(Settings.scheme, Palette.all.count - 1)].palette

    static var background: NSColor { palette.background }
    static var text: NSColor { palette.text }
    static var directory: NSColor { palette.directory }
    static var marked: NSColor { palette.marked }
    static var border: NSColor { palette.border }
    static var cursor: NSColor { palette.cursor }
    static var cursorText: NSColor { palette.cursorText }
    static var inactiveCursor: NSColor { palette.inactiveCursor }
    static var keyBarBackground: NSColor { palette.barBackground }
    static var keyBarNumber: NSColor { palette.barNumber }
    static var keyBarLabel: NSColor { palette.barLabel }
    static var keyBarLabelBackground: NSColor { palette.barLabelBackground }
    static var commandBackground: NSColor { palette.commandBackground }
    static var commandText: NSColor { palette.commandText }
    static var editorText: NSColor { palette.editorText }
    static var editorSelection: NSColor { palette.editorSelection }

    struct DialogColors {
        let background: NSColor
        let text: NSColor
        let border: NSColor
        let fieldBackground: NSColor
        let fieldText: NSColor
        let focusBackground: NSColor
        let focusText: NSColor
    }

    static func dialogColors(warning: Bool) -> DialogColors {
        if warning {
            return DialogColors(
                background: NSColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1), text: .white, border: .white,
                fieldBackground: .white, fieldText: .black, focusBackground: .white, focusText: NSColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1)
            )
        }
        switch Settings.scheme {
        case 0:
            return DialogColors(background: NSColor(white: 0.75, alpha: 1), text: .black, border: .white, fieldBackground: palette.barLabelBackground, fieldText: .black, focusBackground: palette.cursor, focusText: palette.cursorText)
        case 2:
            return DialogColors(background: NSColor(white: 0.93, alpha: 1), text: .black, border: NSColor(white: 0.4, alpha: 1), fieldBackground: .white, fieldText: .black, focusBackground: palette.cursor, focusText: palette.cursorText)
        default:
            return DialogColors(background: NSColor(white: 0.2, alpha: 1), text: .white, border: NSColor(white: 0.6, alpha: 1), fieldBackground: .black, fieldText: .white, focusBackground: palette.cursor, focusText: palette.cursorText)
        }
    }

    static func syntaxColor(_ kind: TokenKind) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        switch (Settings.scheme, kind) {
        case (0, .keyword): return rgb(0xFFE066)
        case (0, .string): return rgb(0x7FFF9F)
        case (0, .comment): return rgb(0x9AA6E8)
        case (0, .number): return rgb(0xFF9AF0)
        case (0, .type): return rgb(0x8FE8FF)
        case (0, .property): return rgb(0xFFB066)
        case (0, .addition): return rgb(0x7FFF9F)
        case (0, .deletion): return rgb(0xFF8A8A)
        case (2, .addition): return rgb(0x1B7F2A)
        case (2, .deletion): return rgb(0xC41A16)
        case (_, .addition): return rgb(0x7FD88F)
        case (_, .deletion): return rgb(0xFF8A80)
        case (2, .keyword): return rgb(0xAD3DA4)
        case (2, .string): return rgb(0xC41A16)
        case (2, .comment): return rgb(0x707F8C)
        case (2, .number): return rgb(0x1C00CF)
        case (2, .type): return rgb(0x3E8087)
        case (2, .property): return rgb(0x326D74)
        case (_, .keyword): return rgb(0xFF7AB2)
        case (_, .string): return rgb(0xFF8170)
        case (_, .comment): return rgb(0x7F8C98)
        case (_, .number): return rgb(0xD9C97C)
        case (_, .type): return rgb(0x5DD8FF)
        case (_, .property): return rgb(0x78C2B3)
        }
    }

    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    static func select(_ index: Int) {
        Settings.scheme = index
        palette = Palette.all[index].palette
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
