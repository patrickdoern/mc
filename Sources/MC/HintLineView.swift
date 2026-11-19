import AppKit

/// Zeile über der Kommandozeile mit einem zufälligen Tipp zur Bedienung, wie beim Original-MC.
final class HintLineView: NSView {
    private static let hints = [
        "Tab wechselt zwischen den Panels.",
        "Einfg oder Leertaste markiert eine Datei, + und − markieren per Muster.",
        "Ctrl-S startet die Schnellsuche im Panel.",
        "⌘L springt zu einem beliebigen Pfad.",
        "⌘K verbindet per SFTP oder FTP (ftp://…) mit einem Server.",
        "⌘D öffnet die Verzeichnis-Hotlist, die Ziffern 1–9 springen direkt.",
        "Ctrl-O blendet das Terminal ein und aus, auf einem SFTP-Panel öffnet es eine ssh-Sitzung.",
        "⌘Y zeigt die Datei in der Übersicht (Quick Look).",
        "F6 und F5 nehmen Masken wie *.bak entgegen.",
        "⇧F4 legt eine neue Datei an und öffnet sie im Editor.",
        "⇧F8 löscht endgültig, F8 legt in den Papierkorb.",
        "⌘Enter fügt den Namen unter dem Cursor in die Kommandozeile ein.",
        "Ctrl-P und Ctrl-N blättern durch die Befehlshistorie.",
        "Enter auf einem Archiv öffnet es wie einen Ordner.",
        "F9 öffnet die Menüzeile, F2 das Benutzermenü.",
        "Tab in der Kommandozeile vervollständigt Befehle und Dateinamen.",
        "⇧⌘H springt ins Home-Verzeichnis.",
    ]

    private var hint = HintLineView.hints.randomElement() ?? ""

    init() {
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.commandBackground.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.font, .foregroundColor: Theme.commandText]
        let available = Int((bounds.width - 12) / Theme.font.maximumAdvancement.width)
        let full = "Hinweis: " + hint
        let text = full.count > available ? String(full.prefix(max(available - 1, 1))) + "…" : full
        (text as NSString).draw(at: NSPoint(x: 6, y: 2), withAttributes: attributes)
    }
}
