# ADR-0007: Nur lokale Panels aktualisieren sich selbst, über FSEvents

- Status: Accepted
- Datum: 2026-11-18

## Kontext

Ändert sich ein angezeigter Ordner von außen, soll das Panel das ohne ⌘R zeigen. Bei SFTP gibt es keine Änderungsmeldung, und Archive sind schreibgeschützte Ansichten.

## Entscheidung

Ein `DirectoryWatcher` auf Basis von FSEvents beobachtet den Ordner eines lokalen Panels (mit `WatchRoot`, damit auch das Löschen des Ordners selbst auffällt, Latenz 0,4 s). Eine Änderung lädt das Panel still nach: keine Ladeanzeige, Cursor und Markierungen bleiben. Der beobachtete Pfad wird mit `realpath` aufgelöst, weil FSEvents `/private/…` meldet und `resolvingSymlinksInPath` das wieder zu `/tmp` verkürzt. SFTP- und Archiv-Panels werden nicht beobachtet; dort bleibt ⌘R.

## Konsequenzen

Das Panel lädt ohne Ladeanzeige nach, Cursor und Markierungen bleiben. Remote-Panels können veralten, bis der Benutzer neu einliest. Bei einem Ereignissturm lädt höchstens ein Nachladen gleichzeitig, weitere werden zu einem zusammengefasst.

## Verworfene Alternativen

Nicht dokumentiert.

## Geltungsbereich und Ausnahmen

Alle Panels mit lokalem Dateisystem. Nicht dokumentiert: Verhalten auf Netzlaufwerken (SMB, NFS).
