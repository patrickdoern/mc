# ADR-0014: Texte der App stehen auf Deutsch im Code und werden über `localized` mit englischer Tabelle übersetzt; die Sprache folgt dem System und lässt sich in der App überschreiben

- Status: Accepted
- Datum: 2026-11-21

Ersetzt ADR-0012. Die Regeln dort gelten unverändert weiter, soweit unten nichts anderes steht; neu ist der Sprachschalter in der App.

## Kontext

Moonlight Commander war ausschließlich auf Deutsch und hatte keine Lokalisierung: Alle sichtbaren Texte standen fest im Code (`Sources/MC` und `Sources/MCCore`). Die App ist inzwischen auch auf Englisch nutzbar (ADR-0012). Dort war entschieden, dass die Sprache ausschließlich der macOS-Systemsprache folgt und es keinen Schalter in der App gibt. Das hat sich als zu eng erwiesen: Nutzer wollen die Sprache der App unabhängig von der Systemsprache wählen können, ohne die Systemeinstellungen aufzusuchen. Die App wird mit eigenem `scripts/bundle.sh` gebaut und signiert (ADR-0003) und nutzt eigene Views mit festen Breiten (ADR-0006).

## Entscheidung

- Der deutsche Text im Code ist der Schlüssel. `localized("…")` (`Sources/MCCore/Localization.swift`) liefert bei Deutsch den Schlüssel unverändert, bei Englisch den Eintrag aus `Sources/MC/Resources/en.lproj/Localizable.strings`. Fehlt der Eintrag, bleibt der deutsche Text stehen. `scripts/bundle.sh` kopiert `en.lproj` ins App-Bundle, gelesen wird aus `Bundle.main`.
- Die Sprache wird beim Start aus `Locale.preferredLanguages` bestimmt: Der erste Eintrag mit Sprachcode `de` oder `en` gilt; ist keiner dabei, gilt Englisch.
- Der Nutzer kann die Sprache in der App wählen: Optionen → Konfiguration → „Sprache:“ mit „Automatisch“, „Deutsch“ und „English“ (die Eigennamen der Sprachen stehen unabhängig von der Oberflächensprache fest). Die Wahl wird als `AppleLanguages` in der UserDefaults-Domain der App gespeichert („Deutsch“ → `["de"]`, „English“ → `["en"]`); „Automatisch“ entfernt den Schlüssel, dann gilt die Systemsprache oder die pro App in den Systemeinstellungen gewählte Sprache. Ein beim Start übergebenes `-AppleLanguages` hat weiter Vorrang und wird nicht gespeichert. Der kleine testbare Baustein dafür ist `AppLanguagePreference` in `MCCore`.
- Eine geänderte Wahl wirkt nach einem Neustart. Die App fragt danach „Jetzt neu starten?“ und startet sich bei Ja über den normalen Beenden-Weg neu (inklusive der Rückfragen zu ungespeicherten Änderungen); bricht der Nutzer das Beenden ab, startet sie nicht neu. Läuft die App nicht aus einem `.app`-Bundle, entfällt die Nachfrage.
- `Info.plist` setzt `CFBundleDevelopmentRegion` auf `de` und `CFBundleLocalizations` auf `de`, `en`.
- `localized` wird nur mit einzeiligen String-Literalen ohne Interpolation als Schlüssel aufgerufen. Werte kommen über Formatstrings (`%@` mit `NSString`, `%ld` für `Int`, bei Bedarf `%1$@`). Pluralformen sind getrennte Schlüssel, es gibt keine `.stringsdict`.
- Ein Test (`LocalizationTableTests`) gleicht Quellcode und Tabelle ab: fehlende und verwaiste Schlüssel, leere Übersetzungen, abweichende Platzhalter und doppelte Schlüssel lassen `swift test` fehlschlagen.
- Ein deutscher Text hat genau eine Übersetzung. Bedeutet derselbe deutsche Text an zwei Stellen etwas anderes, bleibt eine Stelle ohne `localized`, wenn sie in beiden Sprachen gleich lautet, sonst bekommt sie einen eigenen Schlüssel.
- Die Kommandozeilen-Skripte `mc` und `mcedit` und die Dokumenttyp-Namen (`InfoPlist.strings`) folgen der Systemsprache, nicht der Wahl in der App.

## Konsequenzen

Der Umbau bleibt klein, die deutsche Oberfläche und die bestehenden Tests ändern sich nicht. Eine vergessene Übersetzung fällt im Test auf und erscheint in der App als deutscher Text statt leer. Entwicklungsbuilds ohne App-Bundle (`swift build`, `swift run`, `swift test`) zeigen immer Deutsch. Weil die Wahl in `AppleLanguages` der App-Domain liegt, entspricht sie der pro App in den Systemeinstellungen gewählten Sprache; beide verändern denselben Schlüssel, und die App kann den Wert nicht von einer dort getroffenen Wahl unterscheiden. Ein Wechsel wirkt erst nach einem Neustart. Datum- und Größenformat sind sprachunabhängig. Englische Texte müssen in die festen Layouts der eigenen Views passen. Weitere Sprachen brauchen eine weitere Tabelle, eine Anpassung der Sprachbestimmung und einen weiteren Eintrag im Auswahlfeld.

## Verworfene Alternativen

- Nur Systemsprache ohne Schalter in der App (ADR-0012): wurde als zu eng bewertet, siehe Kontext.
- Sofortiges Umschalten ohne Neustart: Menüs, Tastenleiste, Panels und offene Fenster müssten neu aufgebaut werden, und mehrere Texte sind beim Start fest in `static let` und Fenstern gespeichert. Wegen des Aufwands und der Gefahr halb übersetzter Oberfläche verworfen.
- Eigener Schlüssel in den Einstellungen statt `AppleLanguages`, den `Localization` selbst liest: Nicht ausprobiert; `AppleLanguages` genügt, weil `Locale.preferredLanguages` den Wert beim Start ohnehin berücksichtigt.
- `NSLocalizedString` mit Bundle-Lookup: Bei einer nicht unterstützten Systemsprache fällt macOS auf die Entwicklungssprache zurück, hier also Deutsch statt des gewünschten Englisch. Dieser Punkt ist nicht ausprobiert, sondern aus der Funktionsweise abgeleitet.
- String Catalog (`.xcstrings`) und Resource-Bundle von SwiftPM: `scripts/bundle.sh` kopiert nur einzelne Dateien ins Bundle. Eigene Tests dazu: Nicht dokumentiert.
- Englische Quelltexte als Schlüssel: würde das Umschreiben aller vorhandenen Texte erfordern.

## Geltungsbereich und Ausnahmen

Alle sichtbaren Texte der App in `Sources/MC` und `Sources/MCCore`, einschließlich der angelegten Standardtexte der Dateien `ext` und `menu` (sie richten sich beim Anlegen nach der Sprache der laufenden App). Die Skripte `mc` und `mcedit` und die Dokumenttyp-Namen folgen der Systemsprache. Die Website hat eigene Seiten je Sprache und fällt nicht unter dieses ADR (ADR-0013). Eigennamen („Moonlight Commander“, „Norton Commander“) und Marker wie `<DIR>` werden nicht übersetzt.
