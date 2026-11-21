# 0009: Überschreib-Regeln und Kopieroptionen

Status: Ready
Slice: 3/4 (siehe [Roadmap](0006-mc-luecken-roadmap.md)), Ziel-Release 1.6.3

## Ziel
Beim Kopieren und Verschieben lässt sich vorab oder im Konfliktfall festlegen, was bei vorhandenen Dateien passiert („nur wenn neuer“, „nur wenn Größe abweicht“), und im F5/F6-Dialog wählt man, ob Attribute erhalten bleiben und ob symbolischen Links gefolgt wird.

## Anforderungen
- R1 (Muss) `MCCore` bekommt einen Typ `OverwriteRule` (`ask`, `overwrite`, `ifNewer`, `ifSizeDiffers`, `skip`; `Int`-RawValue für die Einstellung, Reihenfolge wie hier) und einen Typ `TransferOptions` (`overwriteRule: OverwriteRule = .ask`, `preserveAttributes: Bool = true`, `followSymlinks: Bool = false`). `FileOperation.init(handlers:options:)` bekommt `options: TransferOptions = TransferOptions()` als zweiten Parameter; alle bestehenden Aufrufe (App und Tests) bleiben mit Standardwerten gültig und verhalten sich wie bisher.
- R2 (Muss) Regeln im Konfliktfall (`FileOperation.shouldOverwrite`, gilt für Kopieren und Verschieben, auch beim Verschieben auf demselben Dateisystem): Gibt es am Ziel eine Datei (Verzeichnisse werden wie bisher zusammengeführt, ohne Konflikt), entscheidet `options.overwriteRule` bzw. die zuletzt im Konfliktdialog gewählte Regel:
  - `ask`: wie bisher der Konfliktdialog (`handlers.resolveConflict`).
  - `overwrite`: ersetzen. `skip`: überspringen (zählt als übersprungen, bei Verschieben bleibt die Quelle stehen).
  - `ifNewer`: ersetzen, wenn die Änderungszeit der Quelle um mehr als 2 Sekunden neuer ist als die des Ziels; sonst überspringen. Sind beide Zeiten nicht bestimmbar (`modified == nil`), wird wie bei `ask` nachgefragt.
  - `ifSizeDiffers`: ersetzen, wenn die Größen verschieden sind; sonst überspringen.
- R3 (Muss) `ConflictChoice` bekommt zwei weitere Fälle `overwriteThenRule(OverwriteRule)` und `skipThenRule(OverwriteRule)`: Die Datei wird ersetzt bzw. übersprungen, und für alle weiteren Konflikte dieser Operation gilt ab sofort die angegebene Regel. Die bestehenden Fälle (`overwrite`, `overwriteAll`, `skip`, `skipAll`, `cancel`) bleiben unverändert und behalten ihre Bedeutung (`overwriteAll` entspricht der Regel `overwrite`, `skipAll` der Regel `skip`).
- R4 (Muss) Konfliktdialog (`Dialogs.conflict`, ADR-0006): bleibt bei den fünf Schaltflächen „Überschreiben“, „Alle überschreiben“, „Überspringen“, „Alle überspringen“, „Abbrechen“ und bekommt zusätzlich eine Auswahl „Für alle weiteren:“ (englisch „For all further:“) mit den Einträgen „Jedes Mal fragen“ (Standard), „Nur wenn neuer“, „Nur wenn Größe abweicht“. Ist „Jedes Mal fragen“ gewählt, liefern „Überschreiben“ und „Überspringen“ wie bisher `overwrite` bzw. `skip`; sonst `overwriteThenRule(…)` bzw. `skipThenRule(…)` mit der gewählten Regel. „Alle überschreiben“ und „Alle überspringen“ liefern wie bisher `overwriteAll` bzw. `skipAll`, unabhängig von der Auswahl.
- R5 (Muss) F5/F6-Dialog (Kopieren und Verschieben in `MainWindowController.swift`; Umbenennen ⇧F6 bleibt unverändert ohne Optionen): Neben dem Zielfeld mit Maske stehen eine Auswahl „Bei vorhandener Datei:“ (englisch „If file exists:“) mit „Jedes Mal fragen“, „Überschreiben“, „Nur wenn neuer“, „Nur wenn Größe abweicht“, „Überspringen“ und die Häkchen „Attribute erhalten“ und „Symbolischen Links folgen“. Der Dialog kommt als neue Funktion in `Dialogs.swift` aus `ClassicDialog` (Feld, Auswahl, Häkchen, Schaltflächen wie die anderen Eingabedialoge, Fokus zuerst im Zielfeld). Die Wahl wird in `Settings` gemerkt (`overwriteRule`, `preserveAttributes` Standard `true`, `followSymlinks` Standard `false`) und beim nächsten Öffnen vorbelegt. Die Optionen gehen als `TransferOptions` an `FileOperation`. Die Einstellung „Überschreiben bestätigen“ (aus) macht bei der Regel „Jedes Mal fragen“ weiterhin „überschreiben ohne Nachfrage“, wie bisher.
- R6 (Muss) „Attribute erhalten“ (`preserveAttributes`): Mit Häkchen ändert sich nichts gegenüber heute (Änderungszeit und Rechte werden übertragen, lokal zusätzlich alles, was `copyfile(COPYFILE_ALL)` mitnimmt). Ohne Häkchen liegt die Änderungszeit der Kopie (Dateien und Ordner) beim Zeitpunkt des Kopierens statt bei der Zeit der Quelle, die Ausführbarkeit der Rechte bleibt erhalten, Besitzer, ACLs und erweiterte Attribute werden nicht übernommen. Bei FTP-Zielen wirkt die Option nicht (keine Zeitstempel setzbar) und erzeugt keine Fehlermeldung.
- R7 (Muss) „Symbolischen Links folgen“ (`followSymlinks`): Ohne Häkchen wie heute (Links werden als Links angelegt). Mit Häkchen wird statt des Links das Ziel kopiert: Ein Link auf eine Datei wird zu einer normalen Datei mit dem Inhalt des Ziels (Größe und Rechte des Ziels), ein Link auf einen Ordner wird als Ordner mit Inhalt kopiert. Ein Link ins Leere ergibt einen Fehler, der wie jeder andere Fehler über die Fehlerabfrage (`resolveFailure`: Überspringen, Alle überspringen, Abbrechen) läuft. Schleifen werden durch eine Tiefengrenze von 40 gefolgten Links entlang eines Pfades abgefangen (Fehlermeldung „Zu viele verschachtelte Symlinks: %@“, englisch „Too many nested symlinks: %@“). Die Fortschrittsberechnung (`scan`) zählt gefolgte Links mit der Größe des Ziels. Das Protokoll `FileSystem` bekommt dafür `func statFollowingLinks(_ path: String) throws -> FileEntry` mit Standardimplementierung `stat`; `LocalFileSystem` (stat(2)) und `SFTPFileSystem` (`LIBSSH2_SFTP_STAT`) überschreiben sie, FTP, Archive und die Panelisierung nutzen den Standard (kennen keine Links oder liefern sie nicht auflösbar). Bei FTP als Ziel erlaubt die Option das Kopieren von Links als Dateien (ohne Option meldet FTP wie heute, dass Symlinks nicht angelegt werden).
- R8 (Muss) Nicht betroffen: Umbenennen, Löschen, das Verschieben ohne Konflikt auf demselben Dateisystem (reine Umbenennung ohne Kopie; die Optionen „Attribute erhalten“ und „Symbolischen Links folgen“ gelten nur, wenn tatsächlich kopiert wird, also bei Kopieren und beim Verschieben zwischen verschiedenen Dateisystemen).
- R9 (Muss) Texte auf Deutsch im Code und auf Englisch in `en.lproj/Localizable.strings` (ADR-0014: nur Literale, `%@` mit `NSString`): „Bei vorhandener Datei:“ = „If file exists:“, „Für alle weiteren:“ = „For all further:“, „Jedes Mal fragen“ = „Ask each time“, „Nur wenn neuer“ = „Only if newer“, „Nur wenn Größe abweicht“ = „Only if size differs“, „Attribute erhalten“ = „Preserve attributes“, „Symbolischen Links folgen“ = „Follow symbolic links“, „Zu viele verschachtelte Symlinks: %@“ = „Too many nested symlinks: %@“. „Überschreiben“ und „Überspringen“ sind als Schlüssel vorhanden und werden wiederverwendet; der vorhandene Schlüssel „Nachfragen“ (Options-Dialog) bleibt unverändert. `LocalizationTableTests` bleibt grün. Bestehende Texte bleiben unverändert.
- R10 (Muss) Tests in `Tests/MCCoreTests` (neue Datei `OverwriteRuleTests.swift` oder Erweiterung von `FileOperationTests.swift`, temporäre Verzeichnisse, `LocalFileSystem.shared`): jede Regel (`overwrite`, `skip`, `ifNewer` mit neuerer, älterer und gleichzeitiger Quelle innerhalb der Toleranz, `ifSizeDiffers` mit gleicher und verschiedener Größe, `ask` mit dem Handler); `overwriteThenRule(.ifNewer)` und `skipThenRule(…)` gelten für alle weiteren Konflikte; Verschieben mit Regel `skip` lässt die Quelle stehen; Kopieren und Verschieben in Unterordnern mit Regel; `preserveAttributes == false`: Änderungszeit der Kopie liegt nach der der Quelle (Quelle mit alter Zeit anlegen) und die Ausführbarkeit bleibt, mit `true`: Änderungszeit gleich; `followSymlinks`: Link auf Datei wird zu normaler Datei mit Inhalt, Link auf Ordner wird als Ordner kopiert, Standard kopiert weiter den Link, Link ins Leere ruft den Fehlerbehandler, Schleife (Link auf den eigenen Elternordner) endet mit dem Fehler der Tiefengrenze und hängt nicht. Die bestehenden Tests bleiben unverändert grün.
- R11 (Muss) `README.md` und `README.en.md`: Der Abschnitt zu Masken beim Kopieren und die Beschreibung des Konfliktdialogs nennen die neuen Regeln, die Auswahl im F5/F6-Dialog und die beiden Häkchen mit ihren Standardwerten und den Grenzen bei FTP.

## Nicht im Umfang
„Anhängen“ und „Fortsetzen“ abgebrochener Übertragungen (mc: Append, Reget), die Option „bestehende Unterordner einbeziehen“ (mc: Dive into subdir; die App führt vorhandene Zielordner ohnehin zusammen und entscheidet je Datei), Übertragung von Besitzer, Gruppe und ACLs über SFTP, eine Einstellung „Überschreiben“ im Options-Dialog (die Voreinstellung steckt im F5/F6-Dialog), Optionen beim Umbenennen und beim Löschen, Schreiben in Archive (Slice 4).

## Betroffene Stellen
- `Sources/MCCore/OperationTypes.swift` (`OverwriteRule`, `TransferOptions`, `ConflictChoice`), `FileOperation.swift` (Optionen, Regeln, Attribute, Links), `FileSystem.swift` (`statFollowingLinks`), `LocalFileSystem.swift`, `SFTPFileSystem.swift`.
- `Sources/MC/Dialogs.swift` (`conflict`, neuer Kopier-/Verschieben-Dialog), `MainWindowController.swift` (F5/F6, Optionen weiterreichen), `OperationRunner.swift` (Optionen an `FileOperation`), `Settings.swift`, `Resources/en.lproj/Localizable.strings`.
- `Tests/MCCoreTests/OverwriteRuleTests.swift` (neu), `README.md`, `README.en.md`.

## Relevante ADRs
- ADR-0006 – Der Konfliktdialog und der F5/F6-Dialog sind eigene Norton-Dialoge (`ClassicDialog`), kein `NSAlert`; Breite begrenzt, deshalb die Auswahl statt weiterer Schaltflächen.
- ADR-0014 – Texte als deutsche Schlüssel mit englischer Tabelle, nur Literale.
- ADR-0009 – Keine neuen Tastenkürzel nötig.
- ADR-0007 – Nach dem Kopieren aktualisieren sich lokale Panels selbst; unverändert.

## Abnahme
- `swift build` ohne Warnung, `swift test` grün (aktuell 112 Tests, plus die neuen).
- Manuell (`./scripts/bundle.sh`, Englisch und Deutsch), mit einem Testordner in `/tmp` mit je zwei Dateien in Quelle und Ziel (eine neuer, eine älter, eine mit gleicher Größe):
  - F5 öffnet den Dialog mit Zielfeld, „If file exists:“ und den zwei Häkchen; die Wahl bleibt nach erneutem Öffnen erhalten.
  - „Only if newer“ ersetzt nur die neuere Datei und überspringt die ältere ohne Rückfrage; „Only if size differs“ entsprechend; „Skip“ überspringt alles; „Overwrite“ ersetzt alles; „Ask each time“ zeigt den Konfliktdialog.
  - Im Konfliktdialog erscheint „For all further:“ mit den drei Einträgen; „Overwrite“ mit „Only if newer“ ersetzt die erste Datei und prüft die folgenden nach der Regel.
  - F6 mit Regel „Skip“ auf einem anderen Dateisystem oder in einen vorhandenen Ordner: Quelle der übersprungenen Datei bleibt stehen.
  - „Preserve attributes“ aus: `stat -f '%Sm'` der Kopie zeigt die aktuelle Zeit statt der alten der Quelle; an: gleiche Zeit.
  - „Follow symbolic links“ an: ein Link auf eine Datei wird als Datei (`ls -l` zeigt keinen `l`) mit dem Inhalt kopiert, ein Link auf einen Ordner als Ordner; aus: Link bleibt Link.
  - FTP-Ziel und SFTP nur, soweit eine Verbindung vorhanden ist (nicht automatisch prüfbar).
- README beider Sprachen nennen die Regeln und Optionen.

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` (ohne Warnung) und `swift test` (aktuell 112 Tests; keine Checks-Sektion in CLAUDE.md, abgeleitet aus Package.swift wie bei den früheren Specs). Zum Schluss `./scripts/bundle.sh` und die Abnahme.

- [ ] T1: Regeln in `MCCore` (R1, R2, R3, R10 Teil 1): `OverwriteRule`, `TransferOptions`, neue `ConflictChoice`-Fälle, `FileOperation.init(handlers:options:)`, Regeln in `shouldOverwrite` für Kopieren und Verschieben; Tests. Dateien: `Sources/MCCore/OperationTypes.swift`, `FileOperation.swift`, `Tests/MCCoreTests/OverwriteRuleTests.swift`.
- [ ] T2: Attribute und Symlinks in `MCCore` (R6, R7, R8, R10 Teil 2, R9 Teil 1): `preserveAttributes` (Zeit der Kopie, Ausführbarkeit), `followSymlinks` mit `FileSystem.statFollowingLinks` (lokal, SFTP, Standard), Tiefengrenze, Fortschrittsberechnung, Fehlertext mit Tabelleneintrag; Tests. Dateien: `Sources/MCCore/FileOperation.swift`, `FileSystem.swift`, `LocalFileSystem.swift`, `SFTPFileSystem.swift`, `en.lproj/Localizable.strings`, `Tests/MCCoreTests/OverwriteRuleTests.swift`.
- [ ] T3: Oberfläche (R4, R5, R9 Teil 2): Auswahl „Für alle weiteren:“ im Konfliktdialog, neuer F5/F6-Dialog mit Auswahl und Häkchen, `Settings`, Weiterreichen der Optionen an `FileOperation`, Übersetzungen. Dateien: `Sources/MC/Dialogs.swift`, `MainWindowController.swift`, `OperationRunner.swift`, `Settings.swift`, `en.lproj/Localizable.strings`.
- [ ] T4: Doku (R11): README deutsch und englisch. Dateien: `README.md`, `README.en.md`.

Danach: Abnahme aus dieser Spec (manuell: F5/F6 mit den Regeln und Häkchen, Konfliktdialog; SFTP/FTP nur, soweit eine Verbindung verfügbar ist).
