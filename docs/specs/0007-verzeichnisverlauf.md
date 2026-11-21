# 0007: Verzeichnisverlauf mit Zurück und Vorwärts

Status: Ready
Slice: 1/4 (siehe [Roadmap](0006-mc-luecken-roadmap.md)), Ziel-Release 1.6.1

## Ziel
Jedes Panel merkt sich die besuchten Ordner und lässt sich mit ⌘← und ⌘→ zurück- und vorwärtsschalten, wie im Finder oder Browser. Eine Verlaufsliste im Menü springt direkt zu einem früheren Ordner. Der Verlauf bleibt beim Beenden erhalten.

## Anforderungen
- R1 (Muss) `MCCore` enthält einen testbaren Baustein ohne AppKit für den Verlauf (z. B. `NavigationHistory<Element: Equatable>`) mit Elementen, einer aktuellen Position und einer Obergrenze (Standard 50). Verhalten:
  - `record(_:)` hängt ein neues Element hinter der aktuellen Position an, macht es zur aktuellen Position und verwirft alle Elemente dahinter (wie im Browser). Ist das Element gleich dem aktuellen, passiert nichts. Wird die Obergrenze überschritten, fällt das älteste Element weg.
  - `back()` und `forward()` liefern das vorige bzw. nächste Element und verschieben die Position, an den Enden liefern sie `nil`; `canGoBack` und `canGoForward` zeigen, ob es geht.
  - `jump(to:)` setzt die Position auf einen Index der Liste; `elements` und `position` sind lesbar.
- R2 (Muss) Jedes Panel (`PanelModel`) hat einen eigenen Verlauf aus Orten (Dateisystem-Objekt und Pfad; gleich, wenn `identity` des Dateisystems und Pfad gleich sind). Jede erfolgreich abgeschlossene Navigation an einen anderen Ort (`navigate(to:on:…)`, auch `goUp`, Öffnen eines Ordners, Gehe zu Pfad, Hotlist, Verbindung zu einem Server, Betreten oder Verlassen eines Archivs) wird aufgezeichnet. Nicht aufgezeichnet werden: automatisches Aktualisieren (`quiet`), `reload` am selben Ort, Änderungen des Cursors und die Navigation durch den Verlauf selbst (R3).
- R3 (Muss) `PanelModel` bekommt `goBack()` und `goForward()`: Sie laden den Ort der vorigen bzw. nächsten Position (Dateisystem und Pfad) ohne ihn erneut aufzuzeichnen und verschieben die Position erst, wenn das Laden erfolgreich war. Schlägt das Laden fehl (z. B. Ordner gelöscht, Verbindung getrennt), bleibt die Position unverändert, das übliche Fehlerdialog-Verhalten (`onFailure`) greift, und der nicht ladbare Eintrag wird aus dem Verlauf entfernt. Nach dem Zurückspringen steht der Cursor auf dem Eintrag, der beim Verlassen des Ordners aktiv war, falls es ihn noch gibt (Name wird beim Verlassen mit im Verlauf gemerkt), sonst oben.
- R4 (Muss) Tastenkürzel im aktiven Panel: ⌘← (zurück) und ⌘→ (vorwärts), in allen Ansichten (Liste, mehrspaltig, Baum, Schnellansicht, Info). Dazu `PanelView` so ändern, dass ⌘← und ⌘→ vor der bisherigen Pfeiltastenbehandlung ausgewertet werden (dort belegen unmodifizierte ←/→ die Spaltennavigation und das Auf- und Zuklappen im Baum, das unverändert bleibt). ⌘↑ und ⌘↓ behalten ihre Bedeutung. Die Kürzel sind auf der deutschen Tastatur direkt erreichbar (ADR-0009).
- R5 (Muss) Menü Links/Rechts (`MainWindowController+Menus.swift`) bekommt im Abschnitt zur Navigation die Einträge „Zurück   ⌘←“, „Vorwärts   ⌘→“ und „Verlauf …“. Zurück und Vorwärts wirken auf das Panel des Menüs (wie die anderen Einträge dort: erst `focus(panel)`), sind abgeschaltet, wenn es nicht geht. „Verlauf …“ öffnet wie die Hotlist ein Popup (`popUp(menu, title:)`) mit allen Einträgen des Verlaufs, der neueste oben, der aktuelle abgehakt; Auswahl springt über `jump` an den Ort (ohne neu aufzuzeichnen). Ist der Verlauf leer, zeigt das Popup einen abgeschalteten Eintrag „Noch kein Verlauf“. Anzeige der Orte: der Pfad, bei Servern und Archiven mit `displayName`.
- R6 (Muss) Speichern: Beim Beenden (`saveState`) speichert jedes Panel die lokalen Orte seines Verlaufs (nur Pfade, höchstens die letzten 50) in den Einstellungen (`leftHistory`, `rightHistory` als `[String]`); Orte auf Servern und in Archiven werden nicht gespeichert. Beim Start wird der Verlauf des Panels daraus aufgebaut, die aktuelle Position ist der letzte Eintrag (das zuletzt geöffnete Verzeichnis ist ohnehin das wiederhergestellte Startverzeichnis; Gleichheit mit dem aktuellen Ort wird nicht doppelt aufgezeichnet). Fehlende Verzeichnisse in der gespeicherten Liste werden erst beim Zurückspringen entfernt (R3).
- R7 (Muss) Neue Texte stehen auf Deutsch im Code und auf Englisch in `en.lproj/Localizable.strings`: „Zurück   ⌘←“ = „Back   ⌘←“, „Vorwärts   ⌘→“ = „Forward   ⌘→“, „Verlauf …“ = „History …“, „Verzeichnisverlauf“ = „Directory History“, „Noch kein Verlauf“ = „No history yet“, plus eine neue Zeile in der F1-Hilfe (`showHelp()` in `MainWindowController.swift`, eigener Schlüssel pro Zeile, z. B. „⌘← und ⌘→ springen im Verzeichnisverlauf zurück und vorwärts.“ = „⌘← and ⌘→ go back and forward in the directory history.“). Bestehende Texte bleiben unverändert; `LocalizationTableTests` bleibt grün.
- R8 (Muss) `README.md` und `README.en.md`: Zeile in der Tastentabelle („⌘← / ⌘→ | Verzeichnisverlauf zurück / vorwärts“ bzw. „Directory history back / forward“) und in der Menüzeile-Beschreibung („Links/Rechts“) die Einträge Zurück, Vorwärts und Verlauf.
- R9 (Muss) Tests in `Tests/MCCoreTests/NavigationHistoryTests.swift` für `NavigationHistory`: Aufzeichnen mit und ohne Dublette, Abschneiden des Vorwärts-Teils nach Zurück, Obergrenze (ältestes fällt weg, Position bleibt gültig), `back`/`forward` an beiden Enden, `jump`, Verhalten bei leerem Verlauf. Die bestehenden Tests bleiben unverändert grün.
- R10 (Kann) Der Name des Ordners, den die Verlaufsliste zeigt, wird bei langen Pfaden in der Mitte gekürzt, damit das Popup nicht zu breit wird.

## Nicht im Umfang
Ein Kürzel für die Verlaufsliste (nur Menü; ⌥⌘H wäre „Andere ausblenden“ und ⌘H „Ausblenden“ in macOS), ein gemeinsamer Verlauf beider Panels, das Speichern von Orten auf Servern oder in Archiven, ein Einstellungspunkt für die Länge (fest 50), mc-Kürzel Alt-Y, Alt-U und Alt-H (unter macOS Sonderzeichen, ADR-0009).

## Betroffene Stellen
- Neu: `Sources/MCCore/NavigationHistory.swift`, `Tests/MCCoreTests/NavigationHistoryTests.swift`.
- `Sources/MC/PanelModel.swift` (Verlauf, `goBack`, `goForward`, Aufzeichnen in `navigate`), `Sources/MC/PanelView.swift` (⌘←, ⌘→), `Sources/MC/MainWindowController+Menus.swift` (Menü), `Sources/MC/MainWindowController+Actions.swift` (Verlaufsliste, Aktionen), `Sources/MC/MainWindowController.swift` (`saveState`, Wiederherstellen, `showHelp()`), `Sources/MC/Resources/en.lproj/Localizable.strings`.
- `README.md`, `README.en.md`.

## Relevante ADRs
- ADR-0009 – Kürzel müssen auf der deutschen Tastatur direkt erreichbar sein; deshalb ⌘← und ⌘→ statt Alt-Y und Alt-U; jedes Kürzel steht im Menü, in der F1-Hilfe und in der README.
- ADR-0006 – Das Popup der Verlaufsliste nutzt die vorhandenen Popup-Bausteine.
- ADR-0014 – Texte als deutsche Schlüssel mit englischer Tabelle, nur Literale.
- ADR-0007 – Live-Aktualisierung nur für lokale Panels; die stille Aktualisierung zeichnet nicht auf (R2).

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (aktuell 78 Tests, plus die neuen).
- Manuell, `./scripts/bundle.sh` und App starten, mit `-AppleLanguages "(en)"` und `(de)`:
  - In mehrere Ordner wechseln (Enter, ⌘↑, Gehe zu Pfad, Hotlist). ⌘← geht Schritt für Schritt zurück, ⌘→ wieder vorwärts; nach einem Zurück und einer neuen Navigation ist Vorwärts abgeschaltet.
  - Cursor und Auswahl: Nach ⌘← steht der Cursor auf dem Ordner, den man zuvor verlassen hat.
  - Menü Links/Rechts: Zurück und Vorwärts sind bei Bedarf abgeschaltet, „Verlauf …“ zeigt die Orte, der aktuelle ist abgehakt, die Auswahl springt dorthin.
  - Beide Panels haben getrennte Verläufe.
  - Ordner löschen, der im Verlauf steht, dann dorthin zurückspringen: Fehlermeldung, Eintrag verschwindet, Position bleibt.
  - SFTP/FTP oder Archiv betreten und mit ⌘← zurück: der vorige lokale Ort erscheint; mit ⌘→ wieder ins Archiv bzw. auf den Server, solange es verbunden ist.
  - App beenden und neu starten: ⌘← springt in die zuvor besuchten lokalen Ordner.
  - ⌘← und ⌘→ funktionieren auch in der mehrspaltigen Ansicht und im Baum (dort bleiben ←/→ ohne ⌘ beim Auf- und Zuklappen bzw. bei der Spaltennavigation).
- F1-Hilfe und README nennen die Kürzel, beide Sprachen.
- Nicht automatisch prüfbar: das Verhalten beim Zurückspringen auf einen getrennten Server (nur manuell mit einer echten Verbindung).

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 78 Tests; keine Checks-Sektion in CLAUDE.md, abgeleitet aus Package.swift wie bei den früheren Specs). Zum Schluss `./scripts/bundle.sh` und die Abnahme.

- [x] T1: Baustein `NavigationHistory` in `MCCore` (R1, R9): Aufzeichnen, Abschneiden, Obergrenze, `back`/`forward`/`jump`, Tests. Dateien: `Sources/MCCore/NavigationHistory.swift`, `Tests/MCCoreTests/NavigationHistoryTests.swift`.
- [x] T2: Verlauf im `PanelModel` (R2, R3, R10 optional): Orte aufzeichnen in `navigate`, `goBack()`, `goForward()`, Entfernen nicht ladbarer Einträge, Cursor auf dem zuvor verlassenen Eintrag, Zugriff auf die Verlaufsliste und das Springen für die Oberfläche, Aufbauen aus gespeicherten lokalen Pfaden. Dateien: `Sources/MC/PanelModel.swift`.
- [x] T3: Oberfläche und Speichern (R4, R5, R6, R7): ⌘←/⌘→ in `PanelView`, Menüeinträge „Zurück“, „Vorwärts“, „Verlauf …“ mit Popup, Speichern und Wiederherstellen in `saveState`, F1-Hilfe-Zeile, Tabelleneinträge. Dateien: `Sources/MC/PanelView.swift`, `MainWindowController+Menus.swift`, `MainWindowController+Actions.swift`, `MainWindowController.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`.
- [x] T4: Doku (R8): README deutsch und englisch (Tastentabelle, Menüzeile). Dateien: `README.md`, `README.en.md`.

Danach: Abnahme aus dieser Spec (die manuelle Prüfung der Tasten und des Popups; der Test mit einem getrennten Server bleibt manuell).
