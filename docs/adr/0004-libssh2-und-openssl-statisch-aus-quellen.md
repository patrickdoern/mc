# ADR-0004: libssh2 und OpenSSL werden aus geprüften Quellen statisch mit Deployment-Target macOS 14 gebaut

- Status: Accepted
- Datum: 2026-11-17

## Kontext

Die gebündelten Homebrew-Dylibs (ADR-0003) erzwingen die macOS-Version des Build-Rechners als Minimum und benötigen beim Bauen Homebrew. Ziel sind zwei Apple-Silicon-Macs, die App soll aber unabhängig von Homebrew und mit macOS 14 als Minimum laufen.

## Entscheidung

`scripts/build-libssh2.sh` lädt OpenSSL und libssh2 in festen Versionen, prüft die SHA-256-Summen, baut beide statisch für arm64 mit `MACOSX_DEPLOYMENT_TARGET=14.0` und legt sie nach `vendor/` (nicht im Repo). `Package.swift` verwendet `vendor/` automatisch, sonst die Homebrew-Bibliotheken. ADR-0003 bleibt für Signierung und Verteilung gültig, ersetzt wird nur die Aussage zur Mindestversion und zu mitgelieferten Dylibs.

## Konsequenzen

Die App ist eine einzelne Datei ohne externe Bibliotheken und läuft ab macOS 14 auf Apple Silicon. Versionen und Prüfsummen im Skript müssen bei Sicherheitsupdates von OpenSSL und libssh2 von Hand angehoben werden. Intel wird nicht unterstützt.

## Verworfene Alternativen

Homebrew-Dylibs bündeln (Mindestversion folgt dem Build-Rechner), Universal-Binary (für die vorhandenen Macs unnötig).

## Geltungsbereich und Ausnahmen

Alle Release-Builds. Für Entwicklung genügt `brew install libssh2`.
