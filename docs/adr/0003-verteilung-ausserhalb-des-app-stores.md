# ADR-0003: macOS Commander wird mit Developer ID außerhalb des App Stores verteilt und bringt seine Bibliotheken mit

- Status: Accepted
- Datum: 2026-11-17

## Kontext

Die App navigiert frei durchs Dateisystem, führt Shell-Befehle aus und nutzt `ssh -G`, `~/.ssh` und den ssh-agent. Das verträgt sich nicht mit der Sandbox, die der Mac App Store verlangt. Zusätzlich hing die App an Homebrew-Pfaden.

## Entscheidung

Die App läuft ohne Sandbox und wird mit Developer ID signiert, mit Hardened Runtime notarisiert und als DMG verteilt (`scripts/dist.sh`). `scripts/bundle.sh` kopiert libssh2 und deren Abhängigkeiten ins Bundle (`Contents/Frameworks`), schreibt die Ladepfade um und signiert alles einzeln.

## Konsequenzen

Die App läuft ohne Homebrew. Die Mindestversion von macOS ergibt sich aus den gebündelten Bibliotheken (derzeit 27.0, nur arm64), weil Homebrew sie für das aktuelle macOS baut. Für ältere Systeme oder Intel müssten libssh2 und OpenSSL selbst mit passendem Deployment-Target gebaut werden. Der App Store ist damit ausgeschlossen.

## Verworfene Alternativen

Mac App Store mit Sandbox (Dateizugriff, Shell und SSH-Agent nicht möglich), statisches Einlinken eigener Builds (aufwendiger, später möglich).

## Geltungsbereich und Ausnahmen

Release-Builds. Entwicklungsbuilds über `swift build` oder Xcode nutzen weiter die Homebrew-Bibliotheken.
