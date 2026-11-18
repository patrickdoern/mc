# ADR-0008: SFTP-Passwörter liegen ausschließlich im macOS-Schlüsselbund

- Status: Accepted
- Datum: 2026-11-17

## Kontext

Verbindungen mit Passwort-Anmeldung sollen nicht bei jedem Verbinden nach dem Passwort fragen. Die App liest sonst nur `~/.ssh` und den ssh-agent (ADR-0002).

## Entscheidung

Der Passwortdialog bietet das Speichern an. Gespeichert wird als generisches Kennwort im Schlüsselbund, Service `digital.doern.mc.sftp`, Konto `user@host:port` (`Keychain.swift`). Beim nächsten Verbinden wird es automatisch benutzt und bei fehlgeschlagener Anmeldung verworfen. Unter Befehl → Gespeicherte Passwörter lassen sich Einträge vergessen. Passwörter erscheinen nie in Einstellungen, Dateien, Logs oder Testausgaben.

## Konsequenzen

Der Zugriff folgt den Regeln des Schlüsselbunds. Schlüssel-Passphrasen werden nicht gespeichert; ob das so bleiben soll, ist nicht dokumentiert.

## Verworfene Alternativen

Nicht dokumentiert.

## Geltungsbereich und Ausnahmen

Alle SFTP-Verbindungen mit Passwort. Tests verwenden nur selbst erzeugte Wegwerf-Passwörter auf lokalen Testservern.
