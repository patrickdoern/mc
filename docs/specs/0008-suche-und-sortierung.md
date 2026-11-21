# 0008: Suche und Sortierung

Status: Ready
Slice: 2/4 (siehe [Roadmap](0006-mc-luecken-roadmap.md)), Ziel-Release 1.6.2

## Ziel
„Datei suchen“ findet auf Wunsch ohne Beachtung der Groß-/Kleinschreibung und mit regulären Ausdrücken, in Name und Inhalt. Die Panels lassen sich zusätzlich nach Zugriffszeit, Statusänderung und Erstellungszeit sortieren, und die Zeitspalte zeigt die Zeit des gewählten Sortierschlüssels.

## Anforderungen
- R1 (Muss) `SearchCriteria` (`Sources/MCCore/FileSearch.swift`) bekommt zwei Optionen: `caseSensitive: Bool` und `useRegex: Bool` (Standard jeweils `false`; die bisherigen Aufrufer und Tests bleiben mit Standardwerten gültig). `FileSearch.run` wertet sie aus:
  - **Name, Maske** (`useRegex == false`): wie bisher `fnmatch` mit Maske (`*`, `?`, `[…]`); die Groß-/Kleinschreibung wird nur bei `caseSensitive == true` beachtet (bisher wurde sie immer ignoriert, das bleibt der Standard).
  - **Name, regulärer Ausdruck** (`useRegex == true`): `NSRegularExpression` über den Dateinamen (ohne Pfad), Treffer überall im Namen (nicht verankert); Groß-/Kleinschreibung wird ohne `caseSensitive` ignoriert. Ist das Namensfeld leer, passt jeder Name (wie bisher `*`).
  - **Inhalt, einfacher Text**: Mit `caseSensitive == true` wie bisher byteweise; ohne wird der Dateiinhalt als UTF-8 gelesen (ungültige Bytes durch Ersatzzeichen ersetzt) und ohne Beachtung der Groß-/Kleinschreibung durchsucht. Das ist eine bewusste Änderung des Standards: Die Inhaltssuche war bisher immer groß-/kleinschreibungsabhängig, ist jetzt ohne Häkchen unabhängig davon.
  - **Inhalt, regulärer Ausdruck**: `NSRegularExpression` über den als UTF-8 gelesenen Inhalt (mehrzeilig: `^` und `$` gelten je Zeile), Groß-/Kleinschreibung wie oben.
  - Unverändert: Inhaltssuche nur im lokalen Dateisystem, keine Symlinks, Dateien bis 50 MB, Abbruch über `isCancelled`.
- R2 (Muss) Ungültiger regulärer Ausdruck: `SearchCriteria` bietet eine Prüfung (z. B. `func validate() throws`), die bei `useRegex` Name und Inhalt kompiliert und bei Fehlern einen `FileError` mit dem Text „Ungültiger regulärer Ausdruck: %@“ (englisch „Invalid regular expression: %@“, Argument: der Ausdruck als `NSString`) wirft. Die Oberfläche ruft sie vor dem Start der Suche auf und zeigt den Fehler im üblichen Fehlerdialog (`Dialogs.show(error:)`), ohne dass die Suche beginnt und ohne dass das Suchfenster geschlossen oder geöffnet wird.
- R3 (Muss) Suchdialog (`findFiles` in `MainWindowController+Actions.swift`): Statt `Dialogs.fields` wird `Dialogs.searchForm` benutzt (Felder „Name:“ und „Inhalt:“ wie bisher, Häkchen „Groß-/Kleinschreibung beachten“ und „Regulärer Ausdruck“, beide vorhandene Schlüssel). `Dialogs.searchForm` bekommt dafür einen optionalen Parameter `message: String = ""` (der Editor ruft es weiter ohne auf). Die Meldung im Dialog zeigt wie bisher „Start: …“ und darunter „Inhaltssuche nur im lokalen Dateisystem.“ (neuer Schlüssel, englisch „Content search only in the local file system.“; der bisherige Schlüssel mit „Groß-/Kleinschreibung wird beachtet“ entfällt, ebenso sein Tabelleneintrag). Die Wahl der beiden Häkchen wird in den Einstellungen gemerkt (`Settings.findCaseSensitive`, `Settings.findRegex`, Standard je `false`) und beim nächsten Öffnen vorbelegt; Name und Inhalt werden nicht gemerkt.
- R4 (Muss) `FileEntry` (`Sources/MCCore/FileEntry.swift`) bekommt drei weitere optionale Zeiten `accessed`, `changed`, `created` (Standard `nil`, der Initialisierer bleibt mit Standardwerten kompatibel) und einen kleinen Typ `EntryTime` (`modified`, `accessed`, `changed`, `created`) mit `FileEntry.time(_ kind: EntryTime) -> Date?`, der bei fehlender Zeit auf `modified` zurückfällt. Die Dateisysteme liefern, was sie kennen: `LocalFileSystem` alle vier (`st_mtimespec`, `st_atimespec`, `st_ctimespec`, `st_birthtimespec`), `SFTPFileSystem` zusätzlich `accessed` aus `atime` (wenn das Attribut gesetzt ist), FTP und Archive nur `modified`.
- R5 (Muss) Sortierung: `SortKey` (`Sources/MC/PanelModel.swift`, `Int`-RawValue wird gespeichert) bekommt die Fälle `accessTime`, `changeTime`, `creationTime`, hinten angehängt (RawValues 4, 5, 6; gespeicherte Werte 0 bis 3 bleiben gültig). Jeder neue Fall sortiert nach `FileEntry.time(_:)` des passenden `EntryTime` (fehlende Zeit: Änderungszeit, bei Gleichstand nach Name wie bisher). Der Dialog „Sortierreihenfolge“ (`chooseSortOrder`) bietet zusätzlich „Zugriffszeit“, „Statusänderung“ und „Erstellungszeit“ an (Englisch „Access Time“, „Status Change“, „Creation Time“; „Statusänderung“ ist als Schlüssel schon vorhanden und wird wiederverwendet), hinter „Datum“; die Auswahl läuft über den Index.
- R6 (Muss) Anzeige: Die Zeitspalte der Panels (`PanelView`, Zeile mit `Formatting.date(entry.modified)`) zeigt die Zeit des gewählten Sortierschlüssels (`entry.time(...)` für die drei neuen Fälle, sonst wie bisher `modified`). Die Cache-Taste für die Schnellansicht (`PanelView` bildet einen Schlüssel aus `entry.modified`) bleibt unverändert. Das Info-Panel zeigt weiterhin alle Zeiten, die es schon zeigt.
- R7 (Muss) Gespeichert wird der Sortierschlüssel wie bisher über `rawValue` (`saveState`); beim Laden unbekannter Werte (größer als 6) gilt `.name`.
- R8 (Muss) Texte auf Deutsch im Code und auf Englisch in `Sources/MC/Resources/en.lproj/Localizable.strings`: „Ungültiger regulärer Ausdruck: %@“ = „Invalid regular expression: %@“, „Inhaltssuche nur im lokalen Dateisystem.“ = „Content search only in the local file system.“, „Zugriffszeit“ = „Access Time“, „Erstellungszeit“ = „Creation Time“. Der Tabelleneintrag der entfallenden Meldung („Inhaltssuche nur im lokalen Dateisystem, Groß-/Kleinschreibung wird beachtet.“) wird gelöscht; `LocalizationTableTests` bleibt grün. Bestehende Texte bleiben unverändert (Regeln aus ADR-0014: nur Literale, `%@` mit `NSString`).
- R9 (Muss) Tests in `Tests/MCCoreTests`: `FileSearchTests` (temporäres Verzeichnis mit Dateien, Aufruf von `FileSearch.run`): Maske ohne und mit `caseSensitive`; regulärer Ausdruck auf Namen (unverankert, ohne und mit `caseSensitive`); einfache Inhaltssuche mit und ohne `caseSensitive` (auch UTF-8 mit Umlauten); regulärer Ausdruck im Inhalt (`^…$` je Zeile); leeres Namensfeld passt alles; Binärdatei und zu große Datei werden nicht durchsucht oder liefern keinen Absturz; Abbruch über `isCancelled`; `validate()` mit gültigem und ungültigem Ausdruck (Fehlertext enthält den Ausdruck). `FileEntryTests` für `time(_:)` einschließlich Rückfall auf `modified`; ein Test für `LocalFileSystem`, dass `accessed`, `changed` und `created` bei einer Datei gesetzt sind. Die bestehenden Tests bleiben unverändert grün.
- R10 (Muss) `README.md` und `README.en.md`: Der Eintrag „Datei suchen (Name und Inhalt)“ im Menü „Befehl“ nennt die Optionen (Groß-/Kleinschreibung beachten, regulärer Ausdruck); die Sortierreihenfolge nennt die neuen Zeiten und dass bei SFTP nur die Zugriffszeit und bei FTP und Archiven nur die Änderungszeit vorhanden ist (sonst Rückfall auf die Änderungszeit).
- R11 (Kann) Zusätzliche Menüeinträge im macOS-Menü „Darstellung“ („Nach Zugriffszeit sortieren“ usw.) wie die vorhandenen „Nach Datum sortieren“. Nur, wenn es mit vorhandenen Mustern ohne großen Aufwand geht, sonst weglassen.

## Nicht im Umfang
Suche in Archiven (Namen oder Inhalt), Inhaltssuche auf SFTP und FTP, Suche nach Größe, Datum oder Rechten, die Option „Unsortiert“ und die Sortierung nach Inode (mc), frei wählbare Spaltenformate, eigenes Kürzel für die Sortierung (ADR-0009 betrifft nur neue Kürzel, es gibt keine), das Merken der Suchtexte.

## Betroffene Stellen
- `Sources/MCCore/FileSearch.swift`, `FileEntry.swift`, `LocalFileSystem.swift`, `SFTPFileSystem.swift`.
- `Sources/MC/PanelModel.swift` (`SortKey`, Sortierung), `PanelView.swift` (Zeitspalte), `Dialogs.swift` (`searchForm` mit `message`), `MainWindowController+Actions.swift` (`findFiles`, `chooseSortOrder`), `Settings.swift`, `Resources/en.lproj/Localizable.strings`.
- `Tests/MCCoreTests/FileSearchTests.swift`, `FileEntryTests.swift` (neu), `README.md`, `README.en.md`.

## Relevante ADRs
- ADR-0006 – Der Suchdialog bleibt ein Norton-Dialog (`ClassicDialog` über `Dialogs.searchForm`).
- ADR-0014 – Texte als deutsche Schlüssel mit englischer Tabelle, nur Literale; `LocalizationTableTests`.
- ADR-0007 – Live-Aktualisierung; die Sortierung nach neuen Zeiten ändert daran nichts.

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (aktuell 98 Tests, plus die neuen).
- Manuell (`./scripts/bundle.sh`, Englisch und Deutsch): Befehl → Datei suchen:
  - Das Häkchen „Groß-/Kleinschreibung beachten“ aus: Eine Maske wie `*.TXT` findet `a.txt` und `b.TXT`, ein Inhalt wie `hallo` findet „Hallo“ und „HALLO“; mit Häkchen nur exakt.
  - „Regulärer Ausdruck“ an: Name `^foto_\d+\.jpg$` findet passende Dateien; Inhalt `^TODO` findet Zeilenanfänge; ein ungültiger Ausdruck wie `([` zeigt den Fehlerdialog „Invalid regular expression: …“ und startet keine Suche.
  - Beim zweiten Öffnen sind die beiden Häkchen wie zuletzt gesetzt.
  - Unverändert: Suchfenster, Ergebnisliste, „Gehe zu“ und „Als Panel“.
- Optionen → Sortierreihenfolge: „Access Time“, „Status Change“ und „Creation Time“ sind wählbar; die Zeitspalte zeigt danach die jeweilige Zeit (mit `stat -f '%Sa %Sm %Sc %SB' <Datei>` an zwei oder drei Dateien vergleichen), die Sortierung stimmt, „Reverse“ kehrt um.
- Beenden und neu starten: der gewählte Sortierschlüssel bleibt erhalten. Ein Panel auf einem SFTP- oder FTP-Server (soweit vorhanden) fällt bei Erstellungs- und Statusänderungszeit auf die Änderungszeit zurück, ohne Absturz.
- README beider Sprachen nennen die Optionen und Zeiten.

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 98 Tests; keine Checks-Sektion in CLAUDE.md, abgeleitet aus Package.swift wie bei den früheren Specs). Zum Schluss `./scripts/bundle.sh` und die Abnahme.

- [ ] T1: Zeitfelder (R4, R9 Teil 1): `FileEntry` mit `accessed`, `changed`, `created`, `EntryTime` und `time(_:)`; `LocalFileSystem` liefert alle vier Zeiten, `SFTPFileSystem` zusätzlich `accessed`; Tests. Dateien: `Sources/MCCore/FileEntry.swift`, `LocalFileSystem.swift`, `SFTPFileSystem.swift`, `Tests/MCCoreTests/FileEntryTests.swift`.
- [ ] T2: Suchlogik (R1, R2, R9 Teil 2, R8 Teil 1): `SearchCriteria` mit `caseSensitive`, `useRegex`, `validate()`, `FileSearch.run` für Maske, regulären Ausdruck und Inhalt ohne und mit Beachtung der Groß-/Kleinschreibung; Tabelleneintrag für den Fehlertext; Tests. Dateien: `Sources/MCCore/FileSearch.swift`, `Tests/MCCoreTests/FileSearchTests.swift`, `en.lproj/Localizable.strings`.
- [ ] T3: Sortierung und Anzeige (R5, R6, R7, R8 Teil 2, R11 optional): neue `SortKey`-Fälle, Sortierung nach den Zeiten, Zeitspalte, Dialog „Sortierreihenfolge“. Dateien: `Sources/MC/PanelModel.swift`, `PanelView.swift`, `MainWindowController+Actions.swift` (`chooseSortOrder`), `en.lproj/Localizable.strings`, ggf. `MainMenu.swift`/`MainWindowController.swift` für R11.
- [ ] T4: Suchdialog (R3, R8 Teil 3): `Dialogs.searchForm` mit `message`, Häkchen im Dialog „Datei suchen“, Validierung vor dem Start, gemerkte Wahl in `Settings`, Textänderungen in der Tabelle. Dateien: `Sources/MC/Dialogs.swift`, `MainWindowController+Actions.swift` (`findFiles`), `Settings.swift`, `en.lproj/Localizable.strings`.
- [ ] T5: Doku (R10): README deutsch und englisch. Dateien: `README.md`, `README.en.md`.

Danach: Abnahme aus dieser Spec (manuell: Suche mit den Optionen, Sortierung mit den neuen Zeiten; SFTP/FTP nur, soweit eine Verbindung verfügbar ist).
