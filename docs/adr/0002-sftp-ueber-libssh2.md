# ADR-0002: SFTP läuft über libssh2 und liest die Konfiguration über `ssh -G`

- Status: Accepted
- Datum: 2026-11-17

## Kontext

SFTP muss mit der bestehenden SSH-Konfiguration (Aliase, Benutzer, Ports, IdentityAgent wie bei 1Password) funktionieren, ohne diese nachzubauen.

## Entscheidung

Verbindungen nutzen libssh2 aus Homebrew (synchrone API, durch ein Lock je Verbindung serialisiert). Host, Benutzer, Port, Schlüsseldateien und Agent-Socket löst `/usr/bin/ssh -G <alias>` auf. Unbekannte Hostkeys werden nach Rückfrage an `known_hosts` angehängt, geänderte lehnt macOS Commander ab.

## Konsequenzen

Die App hängt zur Laufzeit an `/opt/homebrew/opt/libssh2`. ProxyJump und ProxyCommand werden nicht unterstützt. Symlinks lassen sich per SFTP nicht anlegen, weil libssh2s Symlink-Anfrage vom OpenSSH-Server mit einem Protokollfehler beantwortet wird und die Sitzung danach abbricht.

## Verworfene Alternativen

Citadel/NIOSSH (liest keine ssh_config, große Abhängigkeit), `sftp`-Prozess mit Parsen der Ausgabe (fragil, langsam).

## Geltungsbereich und Ausnahmen

Alle Remote-Dateisysteme.
