# 0002: Englische Oberfläche, Slice 1: Infrastruktur und Hauptfenster

Status: Ready
Slice: 1/3 (siehe [Roadmap](0002-englische-oberflaeche-roadmap.md))

## Ziel
Die App wählt ihre Sprache nach der macOS-Sprache (Deutsch bei Deutsch, sonst Englisch). Danach sind Menüleiste, alle Menüs, Funktionstastenleiste, Panels, Info-Panel und Über-Fenster auf Englisch benutzbar; der Baustein dafür steht und wird durch einen Test gegen vergessene oder verwaiste Übersetzungen abgesichert.

## Anforderungen
- R1 (Muss) `MCCore` enthält einen Lokalisierungs-Baustein ohne AppKit-Abhängigkeit mit der öffentlichen Funktion `localized(_ key: String, _ arguments: CVarArg...) -> String`. Der Schlüssel ist der deutsche Text. Bei deutscher Sprache liefert die Funktion den Schlüssel selbst. Bei englischer Sprache liefert sie den Eintrag aus der englischen Tabelle; fehlt er, bleibt der deutsche Schlüssel stehen (nie leer, kein Absturz). Mit Argumenten ist der Schlüssel ein Formatstring (`%@`, `%d`, bei Umstellung der Wortfolge `%1$@`) und wird mit `String(format:)` aufgelöst.
- R2 (Muss) Die Sprache wird einmal beim ersten Gebrauch bestimmt, aus `Locale.preferredLanguages` (das berücksichtigt auch die pro App in den Systemeinstellungen gewählte Sprache). Es gilt der erste Eintrag, dessen Sprachcode (Teil vor `-` oder `_`, kleingeschrieben) `de` oder `en` ist. Ist keiner dabei oder die Liste leer, gilt Englisch. Beispiele: `["de-DE", "en"]` → Deutsch, `["en-US"]` → Englisch, `["fr-FR", "de"]` → Deutsch, `["fr"]` → Englisch, `["de_AT"]` → Deutsch, `[]` → Englisch.
- R3 (Muss) Die englische Tabelle liegt in `Sources/MC/Resources/en.lproj/Localizable.strings` (UTF-8, Format `"Schlüssel" = "Übersetzung";`) und wird zur Laufzeit aus `Bundle.main` gelesen. Im Entwicklungsbuild ohne App-Bundle (`swift build`, `swift test`) gibt es keine Tabelle; dort erscheinen die deutschen Schlüssel. Der Baustein ist über einen internen Initialisierer mit eingespeister Sprache und Tabelle testbar.
- R4 (Muss) Verpackung: `scripts/bundle.sh` kopiert `en.lproj` vor dem Signieren nach `Contents/Resources/`. `scripts/Info.plist` bekommt `CFBundleDevelopmentRegion` = `de` und `CFBundleLocalizations` = `de`, `en`, damit macOS beide Sprachen für die App anbietet. `Package.swift` schließt `Resources/en.lproj` für das Target `MC` aus (`exclude`), damit SwiftPM keine Warnung über unbehandelte Dateien ausgibt.
- R5 (Muss) Folgende Oberflächen verwenden `localized`, und `en.lproj` enthält deren Übersetzungen:
  - `MainMenu.swift` (macOS-Menüleiste: App-, Ablage-, Bearbeiten-, Darstellung-, Fenstermenü),
  - `MainWindowController+Menus.swift` (Pull-down-Menüs der Menüzeile: Links/Rechts, Datei, Befehl, Optionen),
  - die Funktionstastenleiste samt Kurzbezeichnungen in `MainWindowController.swift`,
  - `HintLineView.swift`, `PanelView.swift`, `FileInfo.swift` (Hinweiszeile, Spaltenköpfe, Fußzeilen, Info-Panel),
  - `AboutPanel.swift` (Beschreibungstext; Link-Texte bleiben).
  Die Menü- und Tastenleistentexte folgen dem Midnight Commander (z. B. „Help“, „Menu“, „View“, „Edit“, „Copy“, „RenMov“, „Mkdir“, „Delete“, „PullDn“, „Quit“). Die Kurzbezeichnungen müssen in die Tastenleiste passen, wie es die deutschen tun.
- R6 (Muss) Menütexte mit Tastenhinweis im Text (z. B. `"Ansicht   F3"`) werden als ganzer String übersetzt; der Hinweis bleibt unverändert. Tastenkürzel und Key-Equivalents ändern sich durch die Übersetzung nicht (ADR-0009).
- R7 (Muss) Anzeigetexte dienen nicht als Bezeichner. Wo ein übersetzter Titel mit einem Wert verglichen oder als Dictionary-Schlüssel genutzt wird, ersetzt eine getrennte Kennung den Vergleich. Vor dem Umstellen mit `grep` prüfen, ob irgendwo auf angezeigte Texte verglichen wird (`==`, `switch`, `contains`, Dictionary-Zugriff).
- R8 (Muss) `localized` wird nur mit einem einzeiligen String-Literal als Schlüssel aufgerufen, ohne Interpolation (`\(`), damit der Prüf-Test (R9) die Schlüssel finden kann. Texte aus Arrays und Tupeln stehen als `localized("…")` im Literal an der Stelle der Definition. Pluralformen sind getrennte Schlüssel, keine `.stringsdict`.
- R9 (Muss) Ein Test in `Tests/MCCoreTests/LocalizationTests.swift` prüft die Tabelle gegen den Quellcode (Pfade über `#filePath`): jeder in `Sources/**/*.swift` per `localized("…")` verwendete Schlüssel steht in `en.lproj/Localizable.strings`; jeder Schlüssel der Tabelle wird irgendwo verwendet; keine Übersetzung ist leer; Schlüssel und Übersetzung haben dieselben Formatplatzhalter; die Datei ist gültig (keine doppelten Schlüssel). Dazu Tests für R1 und R2 (Sprachbestimmung, Nachschlagen mit und ohne Treffer, Formatierung mit Argumenten, Deutsch liefert den Schlüssel).
- R10 (Muss) Datum (`dd.MM.yy HH:mm`) und Größenformat (`Formatting.swift`) bleiben unverändert; sie hängen nicht von der Sprache ab.
- R11 (Muss) Neues ADR-0012 hält die Entscheidung fest: deutscher Text als Schlüssel, englische Tabelle im Bundle, Sprache nur über die Systemsprache mit Englisch als Fallback, kein Schalter in der App, Verwendung nur mit Literalen. Eintrag in `docs/adr/README.md`.
- R12 (Kann) Sehr lange englische Texte werden im Layout geprüft und bei Bedarf gekürzt, statt das Layout zu ändern (ADR-0006: eigene Views, feste Breiten).

## Nicht im Umfang
Ein Sprachschalter in der App, weitere Sprachen, Übersetzung von Dialogen, Fortschrittsanzeigen, Fehlermeldungen, Update-Dialog, Einstellungen, Editor, Viewer, F1-Hilfe, Dokumenttyp-Namen, Skripte und README (Slice 2 und 3), lokalisierte Datums- und Zahlenformate, `.xcstrings`/`.stringsdict`, Wechsel der Sprache zur Laufzeit (Neustart genügt).

## Betroffene Stellen
- Neu: `Sources/MCCore/Localization.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`, `Tests/MCCoreTests/LocalizationTests.swift`, `docs/adr/0012-…md`.
- `Sources/MC/MainMenu.swift`, `MainWindowController+Menus.swift`, `MainWindowController.swift`, `HintLineView.swift`, `PanelView.swift`, `FileInfo.swift`, `AboutPanel.swift`.
- `Package.swift` (`exclude`), `scripts/bundle.sh` (Kopieren von `en.lproj`), `scripts/Info.plist` (`CFBundleDevelopmentRegion`, `CFBundleLocalizations`), `docs/adr/README.md`.

## Relevante ADRs
- ADR-0003 – Die App wird mit Developer ID signiert und notarisiert; `en.lproj` muss vor dem Signieren im Bundle liegen.
- ADR-0006 – Dialoge und Leisten sind eigene Views mit festen Breiten; englische Texte müssen hineinpassen.
- ADR-0009 – Tastenkürzel dürfen sich durch Übersetzungen nicht ändern.

## Abnahme
- `swift build` und `swift test`: alle Tests grün, insbesondere `LocalizationTests`. Nach dem absichtlichen Entfernen eines Schlüssels aus `en.lproj` schlägt der Test fehl (einmal prüfen, dann zurücknehmen).
- `./scripts/bundle.sh` läuft ohne Warnung; `build/Moonlight Commander.app/Contents/Resources/en.lproj/Localizable.strings` ist vorhanden, `plutil -lint` auf die Datei ist ok, `codesign --verify --deep` ist ok.
- Manuell, Englisch: App mit `"build/Moonlight Commander.app/Contents/MacOS/MC" -AppleLanguages "(en)"` starten. Menüleiste, alle Pull-down-Menüs (F9), Funktionstastenleiste, Spaltenköpfe und Fußzeilen der Panels, Info-Panel (Panel-Menü „Info“) und Über-Fenster erscheinen auf Englisch; Tastenleiste ohne abgeschnittene Texte; nicht übersetzte Dialoge bleiben deutsch.
- Manuell, Deutsch: mit `-AppleLanguages "(de)"` sieht alles aus wie zuvor.
- Manuell, Französisch: mit `-AppleLanguages "(fr)"` erscheint Englisch.
- Funktionstasten, Menüs und Kürzel verhalten sich in beiden Sprachen gleich (F3, F5, ⌘K, ⌘D, Ctrl-O).

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` und `swift test` (keine Checks-Sektion in CLAUDE.md; abgeleitet aus Package.swift, wie bei Spec 0001). T2 zusätzlich `./scripts/bundle.sh`.

- [x] T1: Lokalisierungs-Baustein in `MCCore` (R1, R2, Teil von R9): `localized(_:_:)`, Sprachbestimmung, interner Initialisierer mit Sprache und Tabelle, Tests für Sprachbestimmung, Nachschlagen und Formatierung. Dateien: `Sources/MCCore/Localization.swift`, `Tests/MCCoreTests/LocalizationTests.swift`.
- [x] T2: Tabelle, Verpackung und Prüf-Test (R3, R4, R8, Rest von R9): leere `en.lproj/Localizable.strings`, `exclude` in `Package.swift`, Kopieren in `bundle.sh`, `Info.plist`, Test gegen vergessene/verwaiste Schlüssel, leere Übersetzungen, abweichende Platzhalter und doppelte Schlüssel. Dateien: `Sources/MC/Resources/en.lproj/Localizable.strings`, `Package.swift`, `scripts/bundle.sh`, `scripts/Info.plist`, `Tests/MCCoreTests/LocalizationTests.swift`. Zusätzlich: `./scripts/bundle.sh`, `plutil -lint`, `codesign --verify --deep`.
- [x] T3: Menüs (R5 Teil 1, R6, R7): macOS-Menüleiste und alle Pull-down-Menüs mit `localized` und englischen Texten im mc-Stil. Dateien: `Sources/MC/MainMenu.swift`, `Sources/MC/MainWindowController+Menus.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`.
- [x] T4: Tastenleiste, Panels, Info, Über-Fenster (R5 Teil 2, R7, R10, R12): Funktionstastenleiste samt Kurzbezeichnungen, Hinweiszeile, Spaltenköpfe und Fußzeilen, Info-Panel, Beschreibungstext im Über-Fenster; nur Texte dieser Oberflächen, Dialoge in `MainWindowController.swift` bleiben Slice 2. Dateien: `Sources/MC/MainWindowController.swift`, `HintLineView.swift`, `PanelView.swift`, `FileInfo.swift`, `AboutPanel.swift`, `en.lproj/Localizable.strings`.
- [ ] T5: ADR-0012 (R11): Entscheidung festhalten, Index in `docs/adr/README.md` ergänzen. Dateien: `docs/adr/0012-…md`, `docs/adr/README.md`.

Danach: Abnahme aus dieser Spec (Englisch/Deutsch/Französisch per `-AppleLanguages`, Tastenleiste ohne abgeschnittene Texte).
