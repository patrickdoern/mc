# 0003: Englische Oberfläche, Slice 2: Dialoge und Meldungen

Status: Ready
Slice: 2/3 (siehe [Roadmap](0002-englische-oberflaeche-roadmap.md), Mechanismus in [Spec 0002](0002-englische-oberflaeche.md) und ADR-0012)

## Ziel
Alles, was die App den Nutzer fragt, meldet oder als Fehler zeigt, erscheint unter einem englischen System auf Englisch: Bestätigungs-, Eingabe- und Auswahldialoge, Fortschritt, Suchen, Update-Hinweis, Statusmeldungen und die Fehlermeldungen der Dateisysteme. Die deutsche Anzeige bleibt Zeichen für Zeichen unverändert.

## Anforderungen
- R1 (Muss) Alle sichtbaren Texte der folgenden Bereiche laufen über `localized`, und `Sources/MC/Resources/en.lproj/Localizable.strings` enthält ihre englische Übersetzung:
  - die Dialog-Bausteine: `Dialogs.swift`, `ClassicDialog.swift`, `ClassicPopup.swift`, `FindDialog.swift` (Titel, Meldungen, Beschriftungen, Standard-Schaltflächen wie „OK“ und „Abbrechen“, „Überschreiben“ usw.),
  - der Fortschritt und die Hintergrundaufgaben: `OperationRunner.swift`,
  - `AppDelegate.swift` (Beenden-Fragen), `UpdateNotifier.swift` (Erstfrage, Update-Dialog, Meldungen), `PanelModel.swift`, `ShellTerminal.swift`,
  - `MainWindowController.swift` und `MainWindowController+Actions.swift` (Bestätigungen, Eingabeaufforderungen, Popups, Statusmeldungen, Vergleichsmeldungen, Verbindungen-Dialog), soweit sie nicht in R9 ausgenommen sind,
  - die Fehlermeldungen in `Sources/MCCore` (`FileError(…)` und andere von dort angezeigte Texte): `FTPFileSystem`, `SFTPFileSystem`, `SSHSession`, `SSHTarget`, `FTPTarget`, `ArchiveFileSystem`, `FileOperation`, `PanelizedFileSystem`, `LocalFileSystem`, `NameMask`, `PosixPath`, `UpdateCheck`, `HexDump` u. a.
  Maßgeblich ist, dass nach dem Umbau kein sichtbarer deutscher Text mehr außerhalb von `localized` steht, außer den Ausnahmen aus R9.
- R2 (Muss) Die deutsche Anzeige bleibt unverändert: Bei Deutsch liefert jeder umgebaute Text exakt dieselbe Zeichenfolge wie vorher. Texte mit eingesetzten Werten werden Formatstrings, deren deutsches Ergebnis dem früheren Text gleicht (`"\(path): Datei nicht gefunden"` → `localized("%@: Datei nicht gefunden", path as NSString)`).
- R3 (Muss) Formatregeln: `String` und `Substring` als `NSString` übergeben (`as NSString`), `Int` als `%ld`, `Int64` als `%lld`, `Int32` als `%d`, ein Prozentzeichen im Text als `%%`. Bei geänderter Wortfolge im Englischen positionelle Platzhalter (`%1$@`, `%2$@`). Aus Interpolationen wie `"\(count) Ersetzung\(count == 1 ? "" : "en")"` werden getrennte Schlüssel pro Pluralform (R8 aus Spec 0002).
- R4 (Muss) Texte, die ein System oder eine Bibliothek liefert, bleiben unverändert und werden nur als `%@`-Argument eingesetzt: `error.localizedDescription`, `strerror`, `curl_easy_strerror`, Meldungen von libssh2 und `ssh`, Dateinamen, Pfade, Hostnamen, Benutzernamen. Auch `FileError(path:errno:)` bleibt wie es ist.
- R5 (Muss) Meldungen werden im Moment des Auftretens mit `localized` erzeugt (am `throw` bzw. beim Aufbau des Dialogs), nicht als statische Konstanten, die den deutschen Text festhalten. Bestehende Tests in `Tests/MCCoreTests`, die deutsche Fehlertexte prüfen, bleiben unverändert grün (im Entwicklungsbuild liefert `localized` den deutschen Schlüssel).
- R6 (Muss) Mehrdeutige Schlüssel: Derselbe deutsche Text mit unterschiedlicher Bedeutung bekommt unterschiedliche Übersetzungen nur über unterschiedliche deutsche Schlüssel, ohne die deutsche Anzeige zu ändern. Ist das nicht möglich, bleibt die Stelle ohne `localized`, wenn der Text in beiden Sprachen gleich lautet (so wurde es für die Hardlink-Zeile im Info-Panel gelöst). Vor dem Eintragen jedes Schlüssels prüfen, ob er in der Tabelle schon vorkommt (z. B. „Links“, „Rechts“, „Ordner“, „Datei“, „Löschen“, „Kopieren“, „Abbrechen“): gleiche Bedeutung → gemeinsamer Eintrag, abweichende Bedeutung → Rückfrage per Notiz im Bericht und Lösung nach dem Muster oben.
- R7 (Muss) Anzeigetexte dienen nicht als Bezeichner. Wo ein Dialogtext, Schaltflächentitel oder Popup-Eintrag verglichen oder als Schlüssel genutzt wird (z. B. Ergebnis von `Dialogs.form` über Titel, Auswahl über Anzeigetext), wird auf einen Index oder eine Kennung umgestellt. Vor dem Umbau per `grep` prüfen (`==`, `switch`, `contains`, `firstIndex`, Dictionary-Zugriff auf Texte).
- R8 (Muss) `LocalizationTableTests` bleibt grün: kein verwaister, fehlender, leerer oder doppelter Schlüssel, gleiche Platzhalter in Schlüssel und Übersetzung. Weiter gilt R8 aus Spec 0002 (nur einzeilige Literale ohne Interpolation als Schlüssel).
- R9 (Muss) Nicht in diesem Slice (bleiben deutsch, Slice 3): der Editor und der Viewer (`EditorWindowController.swift`, Viewer-Texte, deren Tastenleiste und Hilfezeilen), die F1-Hilfe (der mehrzeilige Hilfetext in `MainWindowController.swift`), `Info.plist`-Dokumenttypen, Skripte, `ext`-Beispieltext, README. Ebenfalls unverändert: Schlüsselwörter der Syntaxhervorhebung (`SyntaxHighlighting.swift`), Datei-, Ordner- und Hostnamen, Marker wie `<DIR>`, Eigennamen.
- R10 (Muss) Dialogbreiten und -höhen: Englische Texte werden nicht abgeschnitten und überlappen nichts. Der Dialog-Baustein misst nach Zeichen (ADR-0006); wo ein englischer Text länger ist als der deutsche, wird der Text gekürzt oder umformuliert, nicht das Layout verändert. Ausnahme: Passt ein längster Text nicht, ohne dass der Baustein erkennbar an seiner Grenze ist, darf der Baustein erweitert werden (Notiz im Bericht).
- R11 (Kann) Die Erstfrage zum Update und der Update-Dialog sprechen den Nutzer auf Englisch ebenso knapp an wie auf Deutsch („Du“ → neutrale Anrede).

## Nicht im Umfang
Editor, Viewer, F1-Hilfe, Dokumenttypen, Skripte, README (Slice 3); Übersetzung von Texten, die macOS, libssh2, libcurl oder `ssh` liefern; Änderungen am Verhalten der Dialoge; lokalisierte Datums- und Zahlenformate; Singular-/Pluralregeln jenseits getrennter Schlüssel.

## Betroffene Stellen
- `Sources/MC/Dialogs.swift`, `ClassicDialog.swift`, `ClassicPopup.swift`, `FindDialog.swift`, `OperationRunner.swift`, `AppDelegate.swift`, `UpdateNotifier.swift`, `PanelModel.swift`, `ShellTerminal.swift`, `MainWindowController.swift`, `MainWindowController+Actions.swift` (ggf. weitere Dateien in `Sources/MC` mit sichtbaren Texten außer den Slice-3-Dateien).
- `Sources/MCCore/*.swift` mit `FileError(…)`-Texten: `FTPFileSystem`, `SFTPFileSystem`, `SSHSession`, `SSHTarget`, `FTPTarget`, `ArchiveFileSystem`, `FileOperation`, `PanelizedFileSystem`, `LocalFileSystem`, `NameMask`, `PosixPath`, `UpdateCheck`, `HexDump`.
- `Sources/MC/Resources/en.lproj/Localizable.strings` (neue Einträge).

## Relevante ADRs
- ADR-0012 – Mechanismus: deutscher Text als Schlüssel, englische Tabelle, nur Literale, Test gegen Tabelle.
- ADR-0006 – Dialoge sind eigene Views mit zeichenbasiertem Layout; englische Texte müssen hineinpassen.
- ADR-0011 – Texte des Update-Hinweises; Inhalt (Zustimmung, Ziel `api.github.com`) darf sich durch die Übersetzung nicht ändern.
- ADR-0008 – Texte rund um Passwort und Schlüsselbund bleiben inhaltlich gleich.

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (insbesondere `LocalizationTableTests` und die bestehenden Tests der Dateisysteme und des Update-Checks).
- Prüfung auf Reste: `grep -rnE '"[^"]*[äöüÄÖÜß][^"]*"' Sources | grep -v 'localized('` zeigt nur noch Treffer in den Ausnahmen aus R9 (Editor, Viewer, F1-Hilfe, Syntaxhervorhebung, Skripte), und eine zweite Durchsicht ohne Umlaut-Filter (`grep -rn 'Dialogs\.' Sources`) zeigt keinen deutschen Text mehr in Dialogaufrufen außerhalb des Editors.
- Deutsch unverändert: `./scripts/bundle.sh`, App mit `-AppleLanguages "(de)"` starten, mehrere Dialoge ansehen (siehe unten) und mit früheren Texten vergleichen; zusätzlich `git diff` darauf prüfen, dass bei umgebauten Stellen nur `localized(…)`/Formatstrings dazukamen.
- Englisch manuell mit `-AppleLanguages "(en)"`: F7 (Ordner anlegen), F8 (Löschen mit Bestätigung), F5/F6 mit Namenskonflikt (Überschreiben-Dialog), F5 für Fortschritt, ⌘K (Verbindungsdialog) mit ungültigem Host (Fehlermeldung), „Go to Path …“ mit nicht vorhandenem Pfad (Fehlerdialog), Suchen-Dialog (Find), „Check for Updates …“ im Menü (Dialog), Beenden mit eingeschalteter Rückfrage, Verbindungen-Dialog. Alles auf Englisch, nichts abgeschnitten, Schaltflächen erreichbar (Enter/Esc).
- Französisch mit `-AppleLanguages "(fr)"`: Dialoge erscheinen auf Englisch.

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 66 Tests, keine Checks-Sektion in CLAUDE.md; abgeleitet aus Package.swift, wie bei Spec 0002). Zum Schluss `./scripts/bundle.sh` und die manuelle Abnahme.

- [x] T1: Dialog-Bausteine und kleine App-Dateien (R1 Teil 1, R2, R3, R6, R7, R8, R10, R11): Standard-Schaltflächen und Texte in `Dialogs.swift`, `ClassicDialog.swift`, `ClassicPopup.swift`, `FindDialog.swift`, `OperationRunner.swift`, `AppDelegate.swift`, `UpdateNotifier.swift`, `PanelModel.swift`, `ShellTerminal.swift` samt Tabelleneinträgen. Dateien: diese Swift-Dateien in `Sources/MC` und `en.lproj/Localizable.strings`.
- [x] T2: Fehlermeldungen in `MCCore` (R1 Teil 2, R2–R5, R8): alle `FileError(…)`- und angezeigten Texte in `FTPFileSystem`, `SFTPFileSystem`, `SSHSession`, `SSHTarget`, `FTPTarget`, `ArchiveFileSystem`, `FileOperation`, `PanelizedFileSystem`, `LocalFileSystem`, `NameMask`, `PosixPath`, `UpdateCheck`, `HexDump` u. a. als Formatstrings mit `localized`; Tests der Dateisysteme bleiben unverändert grün. Dateien: `Sources/MCCore/*.swift`, `en.lproj/Localizable.strings`.
- [ ] T3: `MainWindowController.swift` (R1 Teil 3, R2, R3, R6, R7): Bestätigungen, Eingabeaufforderungen, Status- und Popup-Texte; der F1-Hilfetext bleibt deutsch (R9). Dateien: `Sources/MC/MainWindowController.swift`, `en.lproj/Localizable.strings`.
- [ ] T4: `MainWindowController+Actions.swift` (R1 Teil 4, R2, R3, R6, R7): Aktionsdialoge, Vergleichsmeldungen, Verbindungen-Dialog, Fehlertexte, Popups (größter Block, rund 60 Texte). Dateien: `Sources/MC/MainWindowController+Actions.swift`, `en.lproj/Localizable.strings`.

Danach: Reste-Prüfung per `grep` (R1, R9), Abnahme aus dieser Spec (Englisch, Deutsch, Französisch, Layout der Dialoge).
