# 0005: Sprachumschalter in der App

Status: Ready

## Ziel
Der Nutzer wählt die Sprache der App unter Optionen → Konfiguration selbst: „Automatisch“ (wie bisher die Systemsprache, sonst Englisch), „Deutsch“ oder „English“. Nach der Auswahl startet sich die App auf Wunsch neu und erscheint in der gewählten Sprache. Das kehrt die Entscheidung „kein Schalter in der App“ aus ADR-0012 um; ein neues ADR ersetzt sie.

## Anforderungen
- R1 (Muss) Die Wahl wird als `AppleLanguages` in den Einstellungen der App (UserDefaults-Domain `digital.doern.mc`) gespeichert, einem Schlüssel, den macOS beim Start der App für `Locale.preferredLanguages` auswertet (eine Liste in der App-Domain wirkt wie eine pro App gewählte Sprache; das ist in der Abnahme zu bestätigen). „Deutsch“ schreibt `["de"]`, „English“ schreibt `["en"]`, „Automatisch“ entfernt den Schlüssel aus der App-Domain (dann gilt die Systemsprache oder die in den Systemeinstellungen pro App gewählte Sprache). Es gibt keine neue Sprachbestimmung: `Localization.shared` liest wie bisher `Locale.preferredLanguages`, das den Wert beim Start berücksichtigt. Ein beim Start übergebenes `-AppleLanguages "(en)"` hat weiter Vorrang und wird nicht gespeichert.
- R2 (Muss) `MCCore` bekommt einen kleinen, testbaren Baustein ohne AppKit (z. B. `AppLanguagePreference` mit den Fällen automatisch, deutsch, englisch): `init(stored:)` bestimmt den Fall aus der in der App-Domain gespeicherten Liste (`nil` oder leer → automatisch; erster Eintrag mit Sprachcode `de` → deutsch, `en` → englisch, Teil vor `-` oder `_`, kleingeschrieben; alles andere → automatisch) und `stored` liefert die zu speichernde Liste (`nil`, `["de"]`, `["en"]`). Tests in `Tests/MCCoreTests` für alle Fälle (auch `["de-DE", "en"]`, `["fr"]`, `[]`, `nil`, `["EN-us"]`) und für die Rundreise.
- R3 (Muss) `Settings` (`Sources/MC/Settings.swift`) bekommt die Einstellung `language`: lesen aus der App-Domain (`UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"]`, damit nicht die Sprachen des Systems als Auswahl erscheinen), schreiben über R2. Beim Setzen wird nur der Schlüssel `AppleLanguages` in der App-Domain gesetzt oder entfernt, sonst nichts.
- R4 (Muss) Der Dialog „Konfiguration“ (`MainWindowController+Actions.swift`) bekommt oben ein Auswahlfeld „Sprache:“ mit den Einträgen „Automatisch“, „Deutsch“, „English“ und der aktuellen Wahl vorbelegt; die bisherigen drei Häkchen bleiben. „Deutsch“ und „English“ sind die Eigennamen der Sprachen und stehen unabhängig von der Oberflächensprache fest als Literale (ohne `localized`); „Automatisch“ und „Sprache:“ laufen über `localized` („Automatic“, „Language:“). Das Ergebnis des Auswahlfelds wird über den Index ausgewertet (keine Vergleiche über Anzeigetexte).
- R5 (Muss) Hat sich die Wahl geändert, speichert die App sie (R3) und fragt danach in einem Norton-Dialog (`Dialogs.confirm`, ADR-0006): Titel „Sprache ändern“, Meldung „Die neue Sprache gilt nach einem Neustart. Jetzt neu starten?“, Schaltflächen „Neu starten“ (Standard) und „Später“ (vorhandener Schlüssel). Bei „Neu starten“ beendet sich die App über den normalen Beenden-Weg (inkl. Nachfrage bei ungespeicherten Änderungen im Editor, `applicationShouldTerminate`) und startet danach neu. Bricht der Nutzer das Beenden ab, wird nicht neu gestartet. Bei „Später“ gilt die Sprache beim nächsten Start. Hat sich die Wahl nicht geändert, erscheint keine Nachfrage.
- R6 (Muss) Neustart: Die App merkt sich den Wunsch (Flag im `AppDelegate`) und startet in `applicationWillTerminate` eine neue Instanz desselben Bundles (z. B. `/usr/bin/open -n <Bundle-Pfad>` über `Process`, nicht blockierend). Läuft die App nicht aus einem `.app`-Bundle (`swift run`, Entwicklungsbuild), wird die Nachfrage aus R5 nicht angezeigt; die Einstellung wird trotzdem gespeichert.
- R7 (Muss) Die Dialog-Beschriftungen aus R4 und R5 stehen in `en.lproj/Localizable.strings`; sonst kommt kein neuer Text hinzu, und die deutsche und englische Anzeige aller anderen Stellen bleibt unverändert. `LocalizationTableTests` bleibt grün; die Regeln aus ADR-0012 und den Specs 0002 bis 0004 gelten (nur Literale, `%@` mit `NSString`, `Int` mit `%ld`).
- R8 (Muss) Neues ADR-0014 hält die Entscheidung fest: Sprachwahl in der App über `AppleLanguages` der App-Domain mit „Automatisch“ als Voreinstellung, Wirkung nach Neustart mit Nachfrage, Fallback Englisch, die übrigen Regeln aus ADR-0012 gelten unverändert (deutscher Text als Schlüssel, englische Tabelle, Test gegen Tabelle). ADR-0014 ersetzt ADR-0012: In ADR-0012 wird nur die Statuszeile auf „Superseded by ADR-0014“ geändert; ADR-0014 verweist zurück und übernimmt dessen Regeln vollständig (nicht nur die Änderung). Index in `docs/adr/README.md` ergänzen.
- R9 (Muss) Doku: Der Abschnitt „Sprache“ in `README.md` und `README.en.md` nennt zusätzlich den Schalter unter Optionen → Konfiguration (Neustart nötig) und dass „Automatisch“ der Voreinstellung entspricht. Die Skripte `mc` und `mcedit` richten sich weiter nach der Systemsprache (nicht nach dem Schalter der App); das steht ebenfalls dort. Die Website bleibt unverändert.
- R10 (Kann) Die Auswahl „Sprache:“ zeigt bei „Automatisch“ in Klammern die erkannte Sprache (z. B. „Automatisch (Deutsch)“). Nur wenn es ohne zusätzlichen Schlüsselaufwand geht, sonst weglassen.

## Nicht im Umfang
Sofortiges Umschalten ohne Neustart; weitere Sprachen; Sprachwahl für die Skripte `mc`/`mcedit` (bleiben bei der Systemsprache); Dokumenttyp-Namen (folgen der Systemsprache, `InfoPlist.strings`); Umstellen bereits angelegter Dateien `ext` und `menu` (der Standardtext richtet sich beim Anlegen nach der Sprache der laufenden App); Änderungen an der Website; Versionsnummer und Release (eigener Schritt).

## Betroffene Stellen
- Neu: `Sources/MCCore/AppLanguagePreference.swift` und `Tests/MCCoreTests/AppLanguagePreferenceTests.swift`, `docs/adr/0014-…md`.
- `Sources/MC/Settings.swift` (`language`), `Sources/MC/MainWindowController+Actions.swift` (Dialog „Konfiguration“, Nachfrage), `Sources/MC/AppDelegate.swift` (Neustart-Flag, `applicationWillTerminate`), `Sources/MC/Resources/en.lproj/Localizable.strings`.
- `docs/adr/0012-…md` (nur Statuszeile), `docs/adr/README.md`, `README.md`, `README.en.md`.

## Relevante ADRs
- ADR-0012 – bisherige Regel „Sprache nur über Systemsprache, kein Schalter in der App“; wird durch ADR-0014 ersetzt.
- ADR-0006 – Dialoge sind eigene Norton-Views; die Nachfrage nutzt `Dialogs.confirm`, das Auswahlfeld `Dialogs.form` mit `popup:`.
- ADR-0011 – Die App greift nur mit Zustimmung ins Netz; der Schalter ändert daran nichts.

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (neue Tests zu `AppLanguagePreference`, `LocalizationTableTests`).
- Achtung, die Einstellung liegt in den echten App-Einstellungen (`digital.doern.mc`): Vor der manuellen Abnahme den Stand merken (`defaults read digital.doern.mc AppleLanguages`) und danach mit `defaults delete digital.doern.mc AppleLanguages` zurücksetzen.
- `./scripts/bundle.sh`, App starten. Optionen → Konfiguration zeigt oben „Sprache:“ mit „Automatisch“ (bzw. der gespeicherten Wahl); auf Englisch heißt der Dialog „Configuration“, „Language:“ und „Automatic“.
- „English“ wählen, bestätigen: Die Nachfrage „Sprache ändern“ erscheint, „Neu starten“ beendet die App und startet sie auf Englisch; `defaults read digital.doern.mc AppleLanguages` zeigt `en`. Dasselbe mit „Deutsch“ (`de`). „Automatisch“ entfernt den Schlüssel (`defaults read digital.doern.mc AppleLanguages` meldet, dass er in der App-Domain fehlt) und die App folgt wieder der Systemsprache.
- „Später“: kein Neustart, beim nächsten Start gilt die Wahl. Beenden abbrechen (Editor mit ungespeicherten Änderungen): kein Neustart, keine zweite Instanz.
- Unverändert: ohne Änderung der Wahl keine Nachfrage; mit `-AppleLanguages "(fr)"` (Startargument) erscheint Englisch, und das Argument wird nicht gespeichert.
- README: beide Fassungen nennen den Schalter, relative Links funktionieren.
- Nicht automatisch prüfbar: das tatsächliche Wiedererscheinen der App nach dem Neustart in einer fremden Umgebung (Gatekeeper/Notarisierung), da der Test mit dem lokal gebauten Bundle läuft.

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 72 Tests; keine Checks-Sektion in CLAUDE.md, abgeleitet aus Package.swift wie bei den früheren Specs). Zum Schluss `./scripts/bundle.sh` und die Abnahme.

- [x] T1: Baustein in `MCCore` (R2): `AppLanguagePreference` mit `init(stored:)` und `stored`, Tests für alle Fälle und die Rundreise. Dateien: `Sources/MCCore/AppLanguagePreference.swift`, `Tests/MCCoreTests/AppLanguagePreferenceTests.swift`.
- [x] T2: Einstellung, Dialog, Neustart (R1, R3, R4, R5, R6, R7, R10 optional): `Settings.language`, Auswahlfeld „Sprache:“ im Dialog „Konfiguration“, Nachfrage „Sprache ändern“, Neustart über `AppDelegate`, Tabelleneinträge. Dateien: `Sources/MC/Settings.swift`, `Sources/MC/MainWindowController+Actions.swift`, `Sources/MC/AppDelegate.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`.
- [x] T3: ADR und Doku (R8, R9): ADR-0014 (ersetzt ADR-0012, dessen Statuszeile ändert sich), Index, Abschnitt „Sprache“ in beiden READMEs. Dateien: `docs/adr/0014-…md`, `docs/adr/0012-…md` (nur Statuszeile), `docs/adr/README.md`, `README.md`, `README.en.md`.

Danach: Abnahme aus dieser Spec (mit Zurücksetzen der Einstellung per `defaults delete digital.doern.mc AppleLanguages`).
