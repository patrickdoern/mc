import AppKit

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

    static let all: [(name: String, palette: Palette)] = [("Norton Blau", classic), ("Dunkel", dark), ("Hell", light)]
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

    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    static func select(_ index: Int) {
        Settings.scheme = index
        palette = Palette.all[index].palette
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
