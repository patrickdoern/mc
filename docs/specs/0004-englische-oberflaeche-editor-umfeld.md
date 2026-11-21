# 0004: Englische Oberfläche, Slice 3: Editor, Hilfe und Umfeld

Status: Ready
Slice: 3/3 (siehe [Roadmap](0002-englische-oberflaeche-roadmap.md), Mechanismus in [Spec 0002](0002-englische-oberflaeche.md) und ADR-0012)

## Ziel
Auch Editor, Viewer, F1-Hilfe, Dokumenttyp-Namen, die Kommandozeilen-Skripte `mc` und `mcedit`, die angelegte `ext`-Beispieldatei und die README gibt es auf Englisch. Danach ist die App einschließlich ihres Umfelds zweisprachig; die deutsche Anzeige bleibt Zeichen für Zeichen unverändert.

## Anforderungen
- R1 (Muss) Editor und Viewer: Alle sichtbaren Texte in `Sources/MC/EditorWindowController.swift` (Tastenleiste samt Kurzbezeichnungen für Editor und Viewer/`readOnly`, Dialoge „Suchen“, „Ersetzen“, „Codierung“, „Datei einfügen“, Fehlertexte, Statuszeilen, die Hilfezeilen mit der F-Tasten-Aufzählung, die Ersetzungsmeldung mit Einzahl/Mehrzahl) und in `MarkupRenderer.swift`/weiteren Viewer-Dateien, falls dort sichtbarer Text steht, laufen über `localized` mit englischen Einträgen in `en.lproj/Localizable.strings`. Die Regeln aus Spec 0003 gelten unverändert (R2 deutsche Anzeige gleich, R3 Formatplatzhalter und Typen, R4 Systemtexte unübersetzt, R6 mehrdeutige Schlüssel, R7 keine Anzeigetexte als Bezeichner, R8 nur einzeilige Literale). Bereits vorhandene Schlüssel (z. B. „Hilfe“, „Suchen“, „Gehe zu“, „Ende“, „Abbrechen“) werden wiederverwendet, wenn die Bedeutung gleich ist. Die Plural-Meldung `"\(count) Ersetzung\(count == 1 ? "" : "en")"` wird zu zwei vollständigen Schlüsseln.
- R2 (Muss) F1-Hilfe: Der Hilfetext im Dialog „Tastenbelegung“ (`showHelp()` in `MainWindowController.swift`) wird zeilenweise übersetzt: jede Zeile ein eigener einzeiliger `localized`-Schlüssel, die Zeilen werden mit `"\n"` zusammengesetzt, sodass das deutsche Ergebnis dem bisherigen Text Zeichen für Zeichen entspricht. Titel „Tastenbelegung“ ebenfalls. Englisch: knappe Tastenbeschreibung im mc-Stil. Tastennamen für englische Tastaturen anpassen („Backspace“, „Ins“ statt „Einfg“), die Kürzel selbst bleiben (ADR-0009).
- R3 (Muss) Prozentanzeige: Die Fortschrittsanzeige in den Hintergrundaufgaben (`OperationRunner.swift`, `MainWindowController+Actions.swift`) schreibt Prozent sprachabhängig: Deutsch „50 %“ (mit Leerzeichen, wie bisher), Englisch „50%“. Beide Stellen nutzen dieselbe neue Funktion `Formatting.percent(_:)` in `Sources/MC/Formatting.swift` (Schlüssel `localized("%ld %%", …)` mit englischer Übersetzung `%ld%%`). Die deutsche Anzeige bleibt unverändert.
- R4 (Muss) Dokumenttyp-Namen: `en.lproj/InfoPlist.strings` übersetzt die Dokumenttyp-Namen aus `scripts/Info.plist` (Schlüssel ist der deutsche Wert: `"Textdatei" = "Text File";`, `"Ordner" = "Folder";`). `CFBundleDevelopmentRegion` bleibt `de` (ADR-0012), `scripts/bundle.sh` kopiert `en.lproj` ohnehin mit, `Package.swift` schließt `Resources/en.lproj` schon aus. Für Systeme weder in Deutsch noch Englisch bleiben diese zwei Namen deutsch; das ist hingenommen. Ein Test in `Tests/MCCoreTests` liest `scripts/Info.plist` und `en.lproj/InfoPlist.strings` (Pfade über `#filePath`) und prüft, dass jeder `CFBundleTypeName` einen nicht leeren Eintrag in `InfoPlist.strings` hat und umgekehrt jeder Eintrag zu einem Dokumenttyp gehört; die Datei muss gültiges Format haben (`plutil -lint`).
- R5 (Muss) Skripte `scripts/mc` und `scripts/mcedit`: Alle Meldungen („ist nicht installiert“, „existiert nicht“, „Aufruf: mcedit <Datei>...“, „ist ein Ordner“) erscheinen in der Systemsprache: Der erste Eintrag von `defaults read -g AppleLanguages`, dessen Sprachcode `de` oder `en` ist, gilt; sonst Englisch (gleiche Regel wie die App, Spec 0002 R2). Die Sprachbestimmung steht als kleine Funktion in jedem der beiden Skripte (kein gemeinsames Hilfsskript, `install.sh` kopiert nur diese zwei Dateien). Die deutschen Meldungen bleiben Zeichen für Zeichen unverändert, Exit-Codes und Verhalten ebenso.
- R6 (Muss) `ext`-Beispieltext: Beim Anlegen der Datei `~/.config/moonlight-commander/ext` (`FileActions.defaultText` in `Sources/MC/FileActions.swift`) stehen die Kommentarzeilen in der Systemsprache (Deutsch bei Deutsch, sonst Englisch); die Beispielzeilen mit Mustern und Befehlen bleiben gleich. Jede Kommentarzeile ist ein einzeiliger Schlüssel. Bereits vorhandene Dateien werden nicht verändert, und das Einlesen (`FileActions.load()`) bleibt unabhängig von der Sprache.
- R7 (Muss) Englische README: `README.en.md` enthält eine vollständige englische Fassung von `README.md` (alle Abschnitte). Beide Dateien verweisen oben auf die jeweils andere („English version“ / „Deutsche Fassung“). Der Abschnitt zur Webseite nennt in beiden Fassungen `moonlight-commander.org` (englisch unter `/en/`) und GitHub Pages. Ein neuer kurzer Abschnitt in beiden Fassungen erklärt, dass die App nach der macOS-Systemsprache Deutsch oder Englisch zeigt (sonst Englisch) und dass die Sprache pro App in den Systemeinstellungen änderbar ist. Alle Tastenkürzel und Befehle bleiben identisch; Inhalte der deutschen README ändern sich nur im neuen Sprachabschnitt und im Kopf-Verweis.
- R8 (Muss) `LocalizationTableTests` bleibt grün: kein fehlender, verwaister, leerer oder doppelter Schlüssel in `Localizable.strings`, gleiche Platzhalter, nur einzeilige Literale ohne Interpolation (R8 aus Spec 0002).
- R9 (Muss) Nach diesem Slice steht kein sichtbarer deutscher Text mehr außerhalb von `localized` in `Sources` (Ausnahmen: Schlüsselwörter der Syntaxhervorhebung, Namen, Marker, Systemtexte als Argument).
- R10 (Kann) Der Hinweis zu den Skripten in der README (Abschnitt „Kommandozeile“) nennt, dass ihre Meldungen die Systemsprache nutzen.

## Nicht im Umfang
Sprachschalter in der App, weitere Sprachen, übersetzte Namen der Syntaxhervorhebung, Änderungen an der Website (hat eigene Seiten je Sprache), Dokumenttyp-Namen für weitere Sprachen, übersetzte Release-Notizen, Änderung von `CFBundleDevelopmentRegion`.

## Betroffene Stellen
- `Sources/MC/EditorWindowController.swift`, `MarkupRenderer.swift` (falls sichtbarer Text), `MainWindowController.swift` (`showHelp`), `OperationRunner.swift`, `MainWindowController+Actions.swift` (Prozent), `Formatting.swift` (neu `percent`), `FileActions.swift` (`defaultText`).
- `Sources/MC/Resources/en.lproj/Localizable.strings`, neu `Sources/MC/Resources/en.lproj/InfoPlist.strings`, neu ein Test (z. B. `Tests/MCCoreTests/InfoPlistLocalizationTests.swift`).
- `scripts/mc`, `scripts/mcedit`.
- `README.md`, neu `README.en.md`.

## Relevante ADRs
- ADR-0012 – Mechanismus, Systemsprache, Fallback Englisch, `CFBundleDevelopmentRegion` `de`, Geltungsbereich (Skripte, `ext`-Beispieltext, `InfoPlist.strings` sind dort für diesen Slice vorgesehen).
- ADR-0006 – Dialoge sind eigene Views mit zeichenbasiertem Layout; englische Texte müssen hineinpassen.
- ADR-0009 – Tastenkürzel dürfen sich durch Übersetzungen nicht ändern; die F1-Hilfe nennt sie weiterhin.

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (insbesondere `LocalizationTableTests` und der neue Test zu `InfoPlist.strings`); `plutil -lint Sources/MC/Resources/en.lproj/InfoPlist.strings scripts/Info.plist`.
- Reste-Prüfung: `grep -rnE '"[^"]*[äöüÄÖÜß][^"]*"' Sources | grep -v 'localized(' | grep -v SyntaxHighlighting | grep -v 'Localizable.strings\|InfoPlist.strings'` liefert keine Treffer.
- Deutsch unverändert: `./scripts/bundle.sh`, App mit `-AppleLanguages "(de)"` starten, Editor (F4 auf einer Datei), Viewer (F3), F1-Hilfe, Fortschritt vergleichen mit früheren Texten; per `git diff` prüfen, dass bei umgebauten Stellen nur `localized`/Formatstrings dazukamen.
- Englisch manuell mit `-AppleLanguages "(en)"`: Editor und Viewer (Tastenleiste, Suchen, Ersetzen mit Zähler „1 replacement“/„2 replacements“, Codierung, Datei einfügen, Hilfezeile), F1-Hilfe (alle Zeilen, nichts abgeschnitten), Hintergrundaufgaben mit „50%“. Französisch: dieselben Stellen auf Englisch.
- Skripte mit einer Attrappe für `defaults` testen (kein Eingriff in Systemeinstellungen): in einem temporären Ordner ein ausführbares Skript `defaults` anlegen, das `("en-US")` bzw. `("de-DE")` ausgibt, mit `PATH=<Ordner>:$PATH ./scripts/mc /nicht/vorhanden` und `./scripts/mcedit` ohne Argumente, mit einem Ordner, und mit entferntem `/Applications`-Pfad (nur gedanklich, nicht löschen) prüfen; Meldungen auf Englisch bei `en-US` und `fr-FR`, auf Deutsch bei `de-DE`, Exit-Code jeweils 1.
- `ext`-Beispieltext: mit einem temporär gesetzten `HOME` (leeres Verzeichnis) die App einmal in Englisch und einmal in Deutsch Aktionen öffnen lassen, sodass die Datei angelegt wird, Kommentarzeilen in der jeweiligen Sprache prüfen; die echte Datei in `~/.config` wird dabei nicht angefasst.
- README: beide Dateien gegenlesen, Verweise oben funktionieren (relative Links), Abschnitte und Befehle sind deckungsgleich.
- Dokumenttyp-Namen: nur indirekt prüfbar; nach `lsregister -f` das Bundle neu registrieren und im Finder unter „Informationen“ einer Textdatei bzw. in „Öffnen mit“ nachsehen. Falls das System den Namen nicht übernimmt, ist das ein Hinweis, aber kein Abbruchgrund (R4 hängt nur an Datei und Test).

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 66 Tests; keine Checks-Sektion in CLAUDE.md, abgeleitet aus Package.swift wie bei den Specs 0002 und 0003). Zum Schluss `./scripts/bundle.sh` und die Abnahme.

- [ ] T1: Editor und Viewer (R1, R8): `EditorWindowController.swift` und, falls dort sichtbarer Text steht, `MarkupRenderer.swift` über `localized`, Plural der Ersetzungsmeldung als zwei Schlüssel, Tabelleneinträge. Dateien: `Sources/MC/EditorWindowController.swift`, `Sources/MC/MarkupRenderer.swift`, `en.lproj/Localizable.strings`.
- [ ] T2: F1-Hilfe und Prozentanzeige (R2, R3, R8): `showHelp()` zeilenweise, `Formatting.percent(_:)` an beiden Stellen. Dateien: `Sources/MC/MainWindowController.swift`, `Formatting.swift`, `OperationRunner.swift`, `MainWindowController+Actions.swift`, `en.lproj/Localizable.strings`.
- [ ] T3: Dokumenttyp-Namen und `ext`-Beispieltext (R4, R6, R8): `en.lproj/InfoPlist.strings`, Test gegen `scripts/Info.plist`, `FileActions.defaultText` je Sprache. Dateien: `Sources/MC/Resources/en.lproj/InfoPlist.strings`, `Tests/MCCoreTests/InfoPlistLocalizationTests.swift`, `Sources/MC/FileActions.swift`, `en.lproj/Localizable.strings`.
- [ ] T4: Skripte `mc` und `mcedit` (R5): Sprachbestimmung über `defaults read -g AppleLanguages`, Meldungen in Deutsch und Englisch; Test mit `defaults`-Attrappe. Dateien: `scripts/mc`, `scripts/mcedit`.
- [ ] T5: README (R7, R10): `README.en.md`, Verweise und Sprachabschnitt in beiden Fassungen. Dateien: `README.md`, `README.en.md`.

Danach: Reste-Prüfung (R9) und Abnahme aus dieser Spec.
