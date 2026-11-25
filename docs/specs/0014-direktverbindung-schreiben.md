# 0014: Direktverbindung – Schreiben auf die Freigabe

Status: Ready
Slice: 2/3 (Roadmap: [0013-direktverbindung-roadmap.md](0013-direktverbindung-roadmap.md))

## Ziel
Beim Freigeben kann man „Schreiben erlauben“ ankreuzen. Dann kann der verbindende Mac auf der Freigabe kopieren, verschieben, Ordner anlegen, löschen (in den Papierkorb des freigebenden Macs), umbenennen und Dateien mit F4 bearbeiten. Ohne Häkchen bleibt die Freigabe wie in Slice 1 nur lesbar. Ziel-Release 1.6.15.

## Anforderungen

### Protokoll (MCCore)
- R1 (Muss) Protokollversion 2 (`LinkProtocol.version`). Ein Mac mit 1.6.14 und einer mit 1.6.15 bekommen beim Verbinden die vorhandene Meldung „Die Gegenstelle hat eine andere Version von Moonlight Commander“, statt an einem unbekannten Rahmen abzubrechen.
- R2 (Muss) Neue Nachrichten für das Schreiben: `write(handle, data)` (höchstens `maximumBlock`), `finish(handle)`, `abort(handle)` und `trash(path)`, jeweils mit Antwort `done` oder `error`. `openWrite` (schon vorhanden) liefert `handle`. Kodierung und Dekodierung mit Tests wie in Slice 1.
- R3 (Muss) `hello` der freigebenden Seite enthält, ob Schreiben erlaubt ist. `LinkFileSystem` merkt sich das (`isWritable`).

### Freigebende Seite: Prüfung und Ausführung (`LinkShare`)
- R4 (Muss) `LinkShare(folders:writable:)`. Ist `writable` falsch, werden alle schreibenden Anfragen wie bisher mit „Die Freigabe ist nur lesbar“ abgelehnt.
- R5 (Muss) Ist `writable` wahr, werden `makeDirectory`, `removeFile`, `removeDirectory`, `rename`, `makeSymlink`, `setModified`, `setPermissions`, `openWrite`/`write`/`finish`/`abort` und `trash` auf dem lokalen Dateisystem ausgeführt. Dabei gilt Folgendes, als reine, testbare Prüfung wie in Slice 1:
  - Für Anfragen, die den Eintrag selbst betreffen (`makeDirectory`, `removeFile`, `removeDirectory`, `rename` für Quelle und Ziel, `makeSymlink`, `trash`, Anlegen mit `openWrite`): Der Elternordner wird mit `realpath` aufgelöst und muss unter dem freigegebenen Ordner liegen. Der letzte Namensteil darf nicht leer, `.` oder `..` sein.
  - Für Anfragen, die einem Link folgen würden (`setModified`, `setPermissions`, `openWrite` auf eine vorhandene Datei): Das aufgelöste Ziel muss unter dem freigegebenen Ordner liegen. Ein Link, der hinausführt, wird abgelehnt („Außerhalb der Freigabe“) und nichts außerhalb verändert.
  - Die virtuelle Wurzel `/` und die freigegebenen Ordner selbst lassen sich nicht löschen, umbenennen, in den Papierkorb legen oder ändern („Freigegebene Ordner lassen sich nicht ändern“). In `/` lässt sich nichts anlegen.
  - `rename` nur innerhalb derselben Freigabe, nicht zwischen zwei freigegebenen Ordnern (sonst „Außerhalb der Freigabe“); das Kopieren zwischen ihnen bleibt möglich.
  - `setPermissions` und die Rechte bei `openWrite` werden auf `0o777` begrenzt: Kein setuid, setgid oder Sticky-Bit von außen.
  - `makeSymlink` nur mit relativem Ziel, das lexikalisch in der Freigabe bleibt; absolute oder hinausführende Ziele werden abgelehnt („Außerhalb der Freigabe“).
  - Fehlermeldungen enthalten wie in Slice 1 nur virtuelle Pfade, auch bei voller Platte oder fehlenden Rechten.
- R6 (Muss) `trash(path)` legt den Eintrag (Datei oder Ordner samt Inhalt) in den Papierkorb des freigebenden Macs (`LocalFileSystem.trash`).
- R7 (Muss) Offene Schreib-Handles gehören zur Verbindung. Endet die Verbindung, werden sie mit `abort` geschlossen. Unvollständige Dateien verhalten sich wie bei einem abgebrochenen Kopieren auf SFTP (gleiche Aufräumlogik in `FileOperation`, kein Sonderweg).

### Verbindende Seite (`LinkFileSystem`, `FileOperation`, MC)
- R8 (Muss) `LinkFileSystem.openWriter` liefert einen `FileWriter`, der in Blöcken von höchstens `maximumBlock` schreibt; `finish` und `abort` gehen an die Gegenseite. Die schreibenden Methoden aus Slice 1 werten `done` aus.
- R9 (Muss) Löschen mit F8 auf `mc://` legt in den Papierkorb des freigebenden Macs, wenn „Lokal in den Papierkorb statt endgültig löschen“ eingeschaltet ist; ⇧F8 löscht endgültig. Dafür wird der Papierkorb in `FileOperation.delete` nicht mehr nur für `LocalFileSystem` angeboten, sondern für jedes Dateisystem, das ihn kann (schlichte Fähigkeit, z. B. ein kleines Protokoll `TrashingFileSystem` mit `trash(_:)`, umgesetzt von `LocalFileSystem` und `LinkFileSystem`). Die Abfrage vor dem Löschen sagt „In den Papierkorb von <Name> legen?“ statt „In den Papierkorb legen?“.
- R10 (Muss) Ist die Freigabe nur lesbar (`isWritable` falsch), lehnt die verbindende Seite F5/F6 auf die Freigabe, F7, F8, Umbenennen und Sichern in F4 sofort mit „Die Freigabe ist nur lesbar“ ab, ohne erst Anfragen zu schicken und ohne Fortschrittsfenster. Ist sie schreibbar, funktionieren F5, F6 (auch Verschieben von der Freigabe weg und innerhalb), F7, F8/⇧F8, Umbenennen, F4 (über `writeAllSafely`, also temporäre Datei und Umbenennen) und „Attribute erhalten“ (Zeitstempel, Rechte) wie bei SFTP.
- R11 (Kann) Mehrere `write`-Anfragen gleichzeitig unterwegs (z. B. vier), analog zu den Lese-Anfragen in Slice 1.

### Freigebende Seite: Oberfläche
- R12 (Muss) Der Einrichtungsschritt des Freigabe-Dialogs bekommt das Häkchen „Schreiben erlauben“. Es steht bei jedem Öffnen auf aus und wird nicht gemerkt. Darunter ein Satz: „Der andere Mac kann dann Dateien in diesen Ordnern ändern und löschen.“
- R13 (Muss) Der laufende Freigabe-Dialog zeigt „Freigegeben als „<Name>“ (nur lesen)“ bzw. „(lesen und schreiben)“. Die Statuszeile meldet zusätzlich „<Name> schreibt <Datei>“, „<Name> löscht <Datei>“ und „<Name> ändert <Datei>“ (Umbenennen, Ordner anlegen, Zeitstempel und Rechte), nur mit dem Dateinamen wie beim Lesen.

### Doku, Texte, Tests
- R14 (Muss) Alle neuen Texte deutsch und englisch (ADR-0014, `LocalizationTableTests` grün). README DE/EN, Website DE/EN und F1-Hilfe beschreiben „Schreiben erlauben“ und den Papierkorb des freigebenden Macs; die Aussage „nur lesbar“ aus Slice 1 wird angepasst. Die Datenschutzerklärung (DE/EN) sagt, dass der andere Mac bei erlaubtem Schreiben Dateien in den freigegebenen Ordnern ändern und löschen kann. ADR-0018 bleibt unverändert; der Umgang mit dem Schreiben ist in dieser Spec und im Code festgelegt.
- R15 (Muss) Tests in MCCoreTests:
  - Protokoll: neue Nachrichten, `hello` mit Schreibrecht, Versionsabweichung 1 gegen 2.
  - `LinkShare` mit `writable: false`: alle schreibenden Anfragen abgelehnt.
  - `LinkShare` mit `writable: true`: Anlegen, Schreiben, Umbenennen, Löschen, Papierkorb (in einem Testordner, Papierkorb-Test nur, wenn `trashItem` in der Testumgebung geht, sonst über eine austauschbare Funktion), Zeitstempel, Rechte (auf `0o777` begrenzt), Ablehnung bei `..`, bei Links nach außen für `setPermissions`/`setModified`/`openWrite`, bei Wurzel und freigegebenen Ordnern, bei `rename` zwischen zwei Freigaben, bei absoluten oder hinausführenden Symlink-Zielen; keine absoluten Pfade in Fehlern.
  - Durchlauf über 127.0.0.1: Datei größer als 256 KiB hochladen und Inhalt vergleichen, `writeAllSafely`, Abbruch mitten im Schreiben (Handle wird auf der Gegenseite geschlossen), nur lesbare Freigabe lehnt ab.

## Nicht im Umfang
- Gemerkte Kopplung (Slice 3).
- Schreiben nur in einzelnen der freigegebenen Ordner; das Häkchen gilt für alle.
- Rückgängig machen auf dem freigebenden Mac über die Statuszeile, Protokoll der Änderungen im Dialog.
- Besitzer ändern (chown), erweiterte Attribute und Finder-Etiketten über die Leitung.
- Fortsetzen abgebrochener Übertragungen.

## Betroffene Stellen
- `Sources/MCCore/LinkProtocol.swift` (Version 2, neue Nachrichten, `hello`), `Sources/MCCore/LinkShare.swift` (Schreiben, Prüfungen, Papierkorb, Handles), `Sources/MCCore/LinkServer.swift` (`writable`, neue Statusereignisse), `Sources/MCCore/LinkFileSystem.swift` (`openWriter`, `trash`, `isWritable`)
- `Sources/MCCore/FileOperation.swift` (`delete` mit Papierkorb über eine Fähigkeit statt `as? LocalFileSystem`), `Sources/MCCore/LocalFileSystem.swift` (Fähigkeit umsetzen), ggf. `Sources/MCCore/FileSystem.swift`
- `Sources/MC/ShareDialog.swift` (Häkchen, Anzeige, Statustexte), `Sources/MC/MainWindowController.swift` (Löschen: Papierkorb und Abfragetext für `mc://`, frühe Ablehnung bei nur lesbarer Freigabe), ggf. `MainWindowController+Actions.swift` und `EditorWindowController.swift`
- `Sources/MC/Resources/en.lproj/Localizable.strings`, `README.md`, `README.en.md`, `website/` (Startseite und Datenschutz, DE/EN)
- `Tests/MCCoreTests/LinkProtocolTests.swift`, `LinkShareTests.swift`, `LinkLoopbackTests.swift`

## Relevante ADRs
- ADR-0018: Grundlage der Direktverbindung; Zugriffsprüfung nur auf der freigebenden Seite gilt jetzt auch fürs Schreiben.
- ADR-0011: Netzzugriff nur auf ausdrücklichen Wunsch; Schreiben ist ein zusätzliches, nicht gemerktes Häkchen.
- ADR-0006: Häkchen und Abfragen im Norton-Stil.
- ADR-0014: Texte deutsch im Code, englische Tabelle.

## Abnahme
- `swift build` ohne Warnungen, `swift test` grün.
- Manuell mit zwei Macs, beide mit `./scripts/bundle.sh` gebaut:
  - B gibt ohne „Schreiben erlauben“ frei → A: F5 nach B, F7, F8, Umbenennen, Sichern in F4 → sofort „Die Freigabe ist nur lesbar“, kein Fortschrittsfenster.
  - B gibt mit Häkchen frei, Dialog zeigt „(lesen und schreiben)“ → A: Ordner mit vielen Dateien nach B kopieren (`diff -r` auf B), F6 innerhalb der Freigabe, F7, Umbenennen, F4 auf einer Textdatei ändern und sichern, „Attribute erhalten“ setzt Zeitstempel.
  - F8 auf A → Abfrage nennt den Papierkorb von B, Datei liegt danach im Papierkorb von B; ⇧F8 löscht endgültig.
  - Statuszeile auf B zeigt „schreibt“, „löscht“, „ändert“.
  - Symlink in der Freigabe nach außen: Rechte setzen, Zeitstempel setzen und Überschreiben werden abgelehnt, das Ziel außerhalb bleibt unverändert.
  - Freigegebenen Ordner selbst auf A in `/` löschen oder umbenennen → abgelehnt.
  - Kopieren nach B abbrechen und Freigabe während des Kopierens beenden → Verhalten wie bei abgebrochenem SFTP-Kopieren, keine offenen Dateien auf B.
  - Freigabe-Dialog erneut öffnen → Häkchen steht wieder auf aus.
  - 1.6.14 gegen 1.6.15 → Versionsmeldung.
  - Englische Oberfläche: alle neuen Texte englisch.

## Plan
- [x] T1: Protokoll und freigebende Seite (R1–R7, Teile von R13 und R15): Version 2, neue Nachrichten, `hello` mit Schreibrecht, `LinkShare(folders:writable:)` mit allen Schreibprüfungen, Papierkorb und Schreib-Handles, `LinkServer` mit `writable` und Statusereignissen für Schreiben, Löschen, Ändern. Dateien: `Sources/MCCore/LinkProtocol.swift`, `LinkShare.swift`, `LinkServer.swift`, `Tests/MCCoreTests/LinkProtocolTests.swift`, `LinkShareTests.swift`, ggf. `LinkLoopbackTests.swift` (Anpassung an neue Signaturen).
- [x] T2: Verbindende Seite (R8, R9 ohne Oberfläche, R11, Teile von R15): `LinkFileSystem.openWriter`, `trash`, `isWritable`, Papierkorb als Fähigkeit in `FileOperation.delete` (umgesetzt von `LocalFileSystem` und `LinkFileSystem`), Durchlauftests über 127.0.0.1. Dateien: `Sources/MCCore/LinkFileSystem.swift`, `FileOperation.swift`, `LocalFileSystem.swift`, ggf. `FileSystem.swift`, `Tests/MCCoreTests/LinkLoopbackTests.swift`.
- [x] T3: Oberfläche (R9 Abfragetext, R10, R12, R13): Häkchen „Schreiben erlauben“ (nicht gemerkt), Anzeige „(nur lesen)“/„(lesen und schreiben)“, Statustexte, F8 auf `mc://` mit Papierkorb von <Name>, frühe Ablehnung bei nur lesbarer Freigabe. Dateien: `Sources/MC/ShareDialog.swift`, `Sources/MC/MainWindowController*.swift`, ggf. `EditorWindowController.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`.
- [ ] T4: Texte und Doku (R14): README DE/EN, Website DE/EN (Startseite, Datenschutz), F1-Hilfe, englische Tabelle vollständig.

Checks nach jedem Task: `swift build` ohne Warnungen, `swift test` grün.

Danach: Abnahme (manuell mit zwei Macs).

## Offene Fragen
