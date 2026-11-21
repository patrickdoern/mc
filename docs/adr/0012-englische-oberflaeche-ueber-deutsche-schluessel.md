# ADR-0012: Texte der App stehen auf Deutsch im Code und werden über `localized` mit englischer Tabelle und Systemsprache übersetzt

- Status: Accepted
- Datum: 2026-11-21

## Kontext

Moonlight Commander war ausschließlich auf Deutsch und hatte keine Lokalisierung: Alle sichtbaren Texte standen fest im Code (`Sources/MC` und `Sources/MCCore`). Die App soll zusätzlich auf Englisch laufen. Die App wird mit eigenem `scripts/bundle.sh` gebaut und signiert (ADR-0003), das Dateien einzeln ins Bundle kopiert, und nutzt eigene Views mit festen Breiten (ADR-0006).

## Entscheidung

- Der deutsche Text im Code ist der Schlüssel. `localized("…")` (`Sources/MCCore/Localization.swift`) liefert bei Deutsch den Schlüssel unverändert, bei Englisch den Eintrag aus `Sources/MC/Resources/en.lproj/Localizable.strings`. Fehlt der Eintrag, bleibt der deutsche Text stehen. `scripts/bundle.sh` kopiert `en.lproj` ins App-Bundle, gelesen wird aus `Bundle.main`.
- Die Sprache richtet sich ausschließlich nach der macOS-Systemsprache (`Locale.preferredLanguages`, enthält auch die pro App in den Systemeinstellungen gewählte Sprache). Der erste Eintrag mit Sprachcode `de` oder `en` gilt; ist keiner dabei, gilt Englisch. Einen Sprachschalter in der App gibt es nicht.
- `Info.plist` setzt `CFBundleDevelopmentRegion` auf `de` und `CFBundleLocalizations` auf `de`, `en`.
- `localized` wird nur mit einzeiligen String-Literalen ohne Interpolation als Schlüssel aufgerufen. Werte kommen über Formatstrings (`%@` mit `NSString`, `%d`, bei Bedarf `%1$@`). Pluralformen sind getrennte Schlüssel, es gibt keine `.stringsdict`.
- Ein Test (`LocalizationTableTests`) gleicht Quellcode und Tabelle ab: fehlende und verwaiste Schlüssel, leere Übersetzungen, abweichende Platzhalter und doppelte Schlüssel lassen `swift test` fehlschlagen.
- Ein deutscher Text hat genau eine Übersetzung. Bedeutet derselbe deutsche Text an zwei Stellen etwas anderes, bleibt eine Stelle ohne `localized`, wenn sie in beiden Sprachen gleich lautet, sonst bekommt sie einen eigenen Schlüssel.

## Konsequenzen

Der Umbau bleibt klein, die deutsche Oberfläche und die bestehenden Tests ändern sich nicht. Eine vergessene Übersetzung fällt im Test auf und erscheint in der App als deutscher Text statt leer. Entwicklungsbuilds ohne App-Bundle (`swift build`, `swift run`, `swift test`) zeigen immer Deutsch. Ein Wechsel der Sprache wirkt erst nach einem Neustart. Datum- und Größenformat sind sprachunabhängig. Englische Texte müssen in die festen Layouts der eigenen Views passen. Weitere Sprachen brauchen eine weitere Tabelle und eine Anpassung der Sprachbestimmung.

## Verworfene Alternativen

- Sprachschalter in den Einstellungen: Auf Wunsch des Inhabers nur Systemsprache. Weitere Gründe: Nicht dokumentiert.
- `NSLocalizedString` mit Bundle-Lookup: Bei einer nicht unterstützten Systemsprache fällt macOS auf die Entwicklungssprache zurück, hier also Deutsch statt des gewünschten Englisch. Dieser Punkt ist nicht ausprobiert, sondern aus der Funktionsweise abgeleitet.
- String Catalog (`.xcstrings`) und Resource-Bundle von SwiftPM: `scripts/bundle.sh` kopiert nur einzelne Dateien ins Bundle. Eigene Tests dazu: Nicht dokumentiert.
- Englische Quelltexte als Schlüssel: würde das Umschreiben aller vorhandenen Texte erfordern.

## Geltungsbereich und Ausnahmen

Alle sichtbaren Texte der App in `Sources/MC` und `Sources/MCCore`. Die Skripte `mc` und `mcedit`, der Beispieltext der Datei `ext` und `InfoPlist.strings` gehören ebenfalls dazu, folgen aber in einem späteren Schritt (Spec 0002, Slice 3). Die Website hat eigene Seiten je Sprache und fällt nicht unter dieses ADR. Eigennamen („Moonlight Commander“, „Norton Commander“) und Marker wie `<DIR>` werden nicht übersetzt.
