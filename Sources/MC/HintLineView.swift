import AppKit
import MCCore

/// Zeile über der Kommandozeile mit einem zufälligen Tipp zur Bedienung, wie beim Original-MC.
final class HintLineView: NSView {
    private static let hints = [
        localized("Tab wechselt zwischen den Panels."),
        localized("Einfg oder Leertaste markiert eine Datei, + und − markieren per Muster."),
        localized("Ctrl-S startet die Schnellsuche im Panel."),
        localized("⌘L springt zu einem beliebigen Pfad."),
        localized("⌘K verbindet per SFTP, FTP (ftp://…) oder SMB (smb://…) mit einem Server."),
        localized("Befehl → Freigeben … lässt einen anderen Mac mit Moonlight Commander Ordner lesen, mit „Schreiben erlauben“ auch ändern; er findet sie mit ⌘K als mc://Name."),
        localized("Befehl → Gekoppelte Macs … vergisst Kopplungen und nimmt „Immer zulassen“ zurück."),
        localized("⌘D öffnet die Verzeichnis-Hotlist, die Ziffern 1–9 springen direkt."),
        localized("Ctrl-O blendet das Terminal ein und aus, auf einem SFTP-Panel öffnet es eine ssh-Sitzung."),
        localized("⌘Y zeigt die Datei in der Übersicht (Quick Look)."),
        localized("F6 und F5 nehmen Masken wie *.bak entgegen."),
        localized("⇧F4 legt eine neue Datei an und öffnet sie im Editor."),
        localized("⇧F8 löscht endgültig, F8 legt in den Papierkorb."),
        localized("⌘Enter fügt den Namen unter dem Cursor in die Kommandozeile ein."),
        localized("Ctrl-P und Ctrl-N blättern durch die Befehlshistorie."),
        localized("Enter auf einem Archiv öffnet es wie einen Ordner."),
        localized("F9 öffnet die Menüzeile, F2 das Benutzermenü."),
        localized("Tab in der Kommandozeile vervollständigt Befehle und Dateinamen."),
        localized("⇧⌘H springt ins Home-Verzeichnis."),
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
        let full = localized("Hinweis: ") + hint
        let text = full.count > available ? String(full.prefix(max(available - 1, 1))) + "…" : full
        (text as NSString).draw(at: NSPoint(x: 6, y: 2), withAttributes: attributes)
    }
}
