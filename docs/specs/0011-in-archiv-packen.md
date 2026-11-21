# 0011: In Archiv packen

Status: Ready

## Ziel
Der Nutzer kann markierte Dateien und Ordner eines Panels mit einem Befehl in ein neues oder vorhandenes Archiv (zip, tar, tar.gz, tar.bz2, tar.xz, 7z) packen, ohne vorher ein Archiv von Hand anzulegen. Ziel-Release 1.6.5.

## Anforderungen
- R1 (Muss) `ArchiveFileSystem(path:)` akzeptiert auch einen noch nicht vorhandenen Pfad mit schreibbarer Endung (`isWritable`) und liefert dann ein leeres Archiv (nur `/`). Ohne vorhandene Datei und mit nicht schreibbarer Endung bleibt es ein Fehler wie bisher.
- R2 (Muss) `ArchiveRewriter.apply` legt das Archiv an, wenn die Datei fehlt: Hinzufügungen und neue Ordner werden mit `bsdtar -c` im Format der Endung in eine temporäre Datei im Zielordner geschrieben und atomar umbenannt. Löschen und Umbenennen auf einem fehlenden Archiv ist nicht möglich. Schlägt es fehl, bleibt keine Teil-Datei zurück.
- R3 (Muss) Befehl „In Archiv packen …“ im Menü Befehl mit der Taste ⌥F5 (auch in der Tastenleiste/Hilfe, soweit dort die Befehle stehen). Er wirkt auf die Markierung bzw. den Cursoreintrag des aktiven Panels, wie F5.
- R4 (Muss) Dialog (Norton-Stil, ADR-0006) mit Feld „Archivname“: Vorgabe `<Name>.zip` (ein Eintrag: dessen Name, sonst Name des aktuellen Ordners) im Verzeichnis des **anderen** Panels; ein relativer Name gilt dort, ein absoluter Pfad wie üblich. Das Format ergibt sich aus der Endung (.zip, .tar, .tar.gz/.tgz, .tar.bz2/.tbz, .tar.xz/.txz, .7z). Hat der Name keine schreibbare Endung, meldet der Dialog das und packt nicht.
- R5 (Muss) Existiert das Archiv schon, werden die Einträge hinzugefügt; Konflikte folgen den Überschreib-Regeln und dem Konfliktdialog von F5 (Spec 0009). Ein Archiv-Ziel, das keine schreibbare Endung hat, oder dessen Datei kein lesbares Archiv ist, ergibt eine verständliche Fehlermeldung ohne Änderung.
- R6 (Muss) Ausführung über `FileOperation.copy` in das `ArchiveFileSystem` als eine Transaktion (Spec 0010): das Archiv wird pro Befehl genau einmal geschrieben; Fortschritt, Abbruch (Archiv bleibt unverändert) und Hintergrund wie bei F5. Quelle darf jedes Dateisystem sein (lokal, SFTP, FTP); das Archiv liegt dort, wo das Panel-Verzeichnis liegt, und muss ein lokales Dateisystem sein, sonst Fehlermeldung „Archive lassen sich nur lokal anlegen“.
- R7 (Muss) Verhalten wie F5: Ordner rekursiv, Symlinks als Links (Option „Symbolischen Links folgen“ aus Spec 0009 gilt nicht, kein Dialogfeld), keine macOS-Metadaten (`--no-mac-metadata`), Rechte und Änderungszeit bleiben erhalten. Das Archiv selbst wird nicht in sich gepackt, wenn es im Quellordner liegt (wird übersprungen).
- R8 (Muss) Nach dem Packen werden beide Panels neu gelesen; das neue Archiv ist im Zielpanel sichtbar und wird markiert.
- R9 (Muss) Alle neuen Texte deutsch und englisch (ADR-0014: `localized()` mit einzeiligen Literalen, `en.lproj/Localizable.strings`, `LocalizationTableTests` grün); `README.md` und `README.en.md` (Funktionsliste, Tastenliste) nachziehen.
- R10 (Muss) Tests in MCCoreTests: Anlegen je Format (zip, tar.gz, 7z mindestens; Rückprüfung mit `bsdtar -t` bzw. Lesen über `ArchiveFileSystem`), Hinzufügen zu vorhandenem Archiv, Ordner rekursiv, leere Auswahl, Fehler (nicht schreibbare Endung, kein lokales Ziel), Abbruch hinterlässt keine Datei, Archiv im Quellordner wird nicht in sich gepackt.
- R11 (Kann) Packen von einem Archiv-Panel aus (Quelle ist ein Archiv) funktioniert wie Kopieren zwischen zwei Archiven.

## Nicht im Umfang
- Verschieben mit Packen (Quellen löschen), Passwörter/Verschlüsselung, Kompressionsstufe, zip64-Einstellungen, rar/zst/iso als Ziel.
- Auswahl des Formats über ein Aufklapp-Feld (das Format folgt der Endung im Namen).
- Entpacken als eigener Befehl (geht weiter über F5 aus dem Archiv).

## Betroffene Stellen
`Sources/MCCore/ArchiveFileSystem.swift`, `Sources/MCCore/ArchiveRewriter.swift`, `Sources/MC/MainMenu.swift`, `Sources/MC/MainWindowController+Actions.swift` (neuer Befehl), `Sources/MC/KeyBar.swift`/Hilfetexte soweit Tasten dort stehen, `Sources/MC/Resources/en.lproj/Localizable.strings`, `Tests/MCCoreTests/ArchivePackTests.swift`, `README.md`, `README.en.md`.

## Relevante ADRs
- ADR-0006 – Dialoge im Norton-Stil.
- ADR-0014 – deutsche Texte als Schlüssel, englische Tabelle, Tabellentest.

## Abnahme
- `swift build` ohne Warnungen, `swift test` grün.
- In der App: Dateien markieren, ⌥F5, Name `test.zip` bzw. `test.tar.gz`/`test.7z`, im anderen Panel entsteht das Archiv; Enter darauf zeigt die Einträge, `bsdtar -tf` bestätigt es. Erneut packen mit weiteren Dateien fügt hinzu, Konflikt fragt wie bei F5.
- Name ohne bekannte Endung (`test.rar`) wird abgelehnt; Abbrechen mitten im Packen hinterlässt keine Datei.

## Plan
- [x] T1: Kern (R1, R2, R10 Teil 1): `ArchiveFileSystem` für fehlende Datei, `ArchiveRewriter` legt Archiv an (nur Hinzufügungen/Ordner, atomar, keine Teil-Datei bei Fehler); Tests über `FileOperation.copy` in ein neues Archiv je Format, Hinzufügen zu vorhandenem, Ordner, Abbruch/Fehler. Dateien: `Sources/MCCore/ArchiveFileSystem.swift`, `Sources/MCCore/ArchiveRewriter.swift`, `Tests/MCCoreTests/ArchivePackTests.swift`.
- [ ] T2: Oberfläche und Doku (R3–R9, R10 Rest): Menüeintrag und ⌥F5, Dialog mit Namensprüfung und lokalem Ziel, Packen über `FileOperation.copy` in `ArchiveFileSystem` (Archiv im Quellordner überspringen, Markierung, Neulesen), englische Texte, README deutsch und englisch. Dateien: `Sources/MC/MainMenu.swift`, `Sources/MC/MainWindowController*.swift`, `Sources/MC/Resources/en.lproj/Localizable.strings`, `README.md`, `README.en.md`, ggf. MCCore für das Überspringen.

Danach: Abnahme (manuell in der App).

## Offene Fragen
