# ADR-0015: FTP-Anmeldungen mit Passwort laufen nur über TLS oder nach ausdrücklicher Zustimmung im Klartext

- Status: Accepted
- Datum: 2026-11-21

## Kontext

ADR-0010 ließ `ftp://` TLS nur versuchen (`CURLUSESSL_TRY`). Bietet der Server kein TLS an oder unterdrückt ein Angreifer im Netz das `AUTH TLS`, gingen Nutzer und Passwort stillschweigend im Klartext über die Leitung. Das kritische Review vom 2026-11-21 hat das als Risiko benannt.

## Entscheidung

FTP läuft weiter über das System-libcurl, das Remote-Terminal über `/usr/bin/ssh` (alles Übrige aus ADR-0010 gilt unverändert). Bei `ftp://` mit Nutzer verlangt die App TLS (`CURLUSESSL_ALL`). libcurl bricht dann vor `USER`/`PASS` ab, wenn der Server kein TLS anbietet. Die App fragt in diesem Fall, ob sie unverschlüsselt anmelden soll, und merkt sich die Antwort nur für diese Verbindung. Anonyme Anmeldungen versuchen TLS weiterhin nur (`CURLUSESSL_TRY`), weil dabei kein Geheimnis übertragen wird. `ftps://` erzwingt wie bisher implizites TLS.

## Konsequenzen

Ohne Zustimmung verlässt kein Passwort die App unverschlüsselt. Bei Servern ohne TLS erscheint bei jedem Verbinden eine Rückfrage. Inhalte anonymer Verbindungen können weiterhin im Klartext laufen.

## Verworfene Alternativen

Immer TLS ohne Ausweg wurde verworfen, weil viele Geräte im lokalen Netz (NAS, Drucker) nur unverschlüsseltes FTP können. Eine dauerhaft gespeicherte Ausnahme pro Server wurde verworfen, weil sie eine spätere Herabstufung durch einen Angreifer wieder unbemerkt ließe.

## Geltungsbereich und Ausnahmen

Alle `ftp://`- und `ftps://`-Verbindungen und das Terminal auf SFTP-Panels.
