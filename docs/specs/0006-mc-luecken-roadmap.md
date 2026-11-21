# 0006: Lücken gegenüber dem Midnight Commander schließen – Roadmap

Vier Funktionen des Midnight Commander (mc), die Moonlight Commander bisher fehlen. Jeder Slice ist für sich lauffähig und wird als Patch-Release innerhalb von 1.6 ausgeliefert (1.6.1, 1.6.2, …). Reihenfolge: kleine, schnelle Gewinne zuerst, der größte Eingriff (Archive beschreiben) zuletzt.

Rahmen für alle Slices: Neue Texte deutsch und englisch (ADR-0014: `localized()` nur mit Literalen, `en.lproj/Localizable.strings`, `LocalizationTableTests` grün, `%@` mit `NSString`, `Int` mit `%ld`); eigene Norton-Dialoge (ADR-0006); Kürzel auf deutscher Tastatur direkt erreichbar und im Menü, in der F1-Hilfe und in der README (ADR-0009); `README.md` und `README.en.md` nachziehen.

## Slices

- [x] Slice 1 (1.6.1): [Verzeichnisverlauf mit Zurück und Vorwärts](0007-verzeichnisverlauf.md) – pro Panel, Kürzel ⌘← und ⌘→, Menü, Verlaufsliste, Speicherung beim Beenden
- [x] Slice 2 (1.6.2): [Suche und Sortierung](0008-suche-und-sortierung.md) – Optionen „Groß-/Kleinschreibung ignorieren“ und „reguläre Ausdrücke“ für Name und Inhalt der Dateisuche (bisher Inhalt immer mit Groß-/Kleinschreibung und nur lokal), Sortierung zusätzlich nach Zugriffszeit, Änderungszeit des Eintrags (ctime) und ggf. Inode/Erstellungszeit, Spaltenanzeige beachten; Suche in Archiven nur, wenn es ohne großen Aufwand geht
- [ ] Slice 3 (1.6.3): Überschreib-Regeln und Kopieroptionen – im Konfliktdialog zusätzlich „nur wenn neuer“ (mc: Update), „nur wenn Größe anders“, „anhängen“; beim Kopieren und Verschieben Optionen „Attribute erhalten“ (Zeitstempel, Rechte, Besitzer), „Symbolischen Links folgen“, „bestehende Unterordner einbeziehen“, Wahl wird gemerkt; gilt für lokale Dateisysteme und SFTP, FTP mit seinen bekannten Grenzen (keine Zeitstempel, keine Symlinks)
- [ ] Slice 4 (1.6.4): Archive beschreiben – Hineinkopieren, Löschen und Umbenennen in zip (.zip, .jar, .war), tar (.tar, .tgz/.tar.gz, .tbz/.tar.bz2, .txz/.tar.xz) und 7z mit dem mitgelieferten `bsdtar` (libarchive); jede Änderung schreibt das Archiv neu (temporäre Datei, danach ersetzen), pro Operation nur einmal; Fortschritt, Abbruch und Hintergrund wie bei anderen Operationen; .rar und .iso bleiben nur lesbar

Slice 2 bis 4 sind nur grob beschrieben und bekommen jeweils eine eigene Spec, wenn sie an der Reihe sind.
