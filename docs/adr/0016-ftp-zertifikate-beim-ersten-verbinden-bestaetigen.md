# ADR-0016: FTP-Zertifikate ohne bekannte Zertifizierungsstelle werden beim ersten Verbinden bestätigt und gespeichert

- Status: Accepted
- Datum: 2026-11-21

## Kontext

Seit ADR-0015 laufen FTP-Anmeldungen über TLS. Viele FTP-Server (FileZilla Server, NAS-Geräte) bringen ab Werk ein selbstsigniertes Zertifikat mit. libcurl lehnt es ab, die Verbindung scheitert mit „SSL peer certificate or SSH remote key was not OK“, und es gab keinen Ausweg.

## Entscheidung

Scheitert die Prüfung des Zertifikats, ruft die App das Zertifikat in einem zweiten Anlauf ab. Dieser Anlauf bricht durch einen absichtlich falschen Public-Key-Pin direkt nach dem TLS-Handshake ab, noch bevor Benutzer oder Passwort gesendet werden. Die App zeigt Inhaber, Aussteller, Ablaufdatum und den SHA-256-Fingerabdruck. Nach Zustimmung landet das Zertifikat als PEM in `~/.config/moonlight-commander/ftp-certificates/<host>_<port>.pem`. Künftige Verbindungen zu diesem Host und Port vertrauen nur diesem Zertifikat (`CURLOPT_CAINFO`); der Hostname wird dabei nicht mehr geprüft, weil das gespeicherte Zertifikat die Identität festlegt. Ändert sich das Zertifikat, fragt die App erneut und weist deutlich auf die Änderung hin.

## Konsequenzen

Selbstsignierte Server funktionieren nach einer einmaligen Bestätigung, wie bei SSH-Hostkeys (Trust on First Use). Ein Angreifer bei der allerersten Verbindung bliebe unerkannt, wenn der Nutzer den Fingerabdruck nicht prüft. Läuft ein selbstsigniertes Zertifikat ab und wird erneuert, kommt die Rückfrage erneut. Gemerkte Zertifikate lassen sich bisher nur durch Löschen der Datei vergessen.

## Verworfene Alternativen

Die Zertifikatsprüfung abzuschalten (`CURLOPT_SSL_VERIFYPEER` aus) wurde verworfen, weil TLS dann gegen Angreifer im Netz nichts mehr nützt. Ablage im Schlüsselbund wurde verworfen, weil Zertifikate keine Geheimnisse sind und eine Datei pro Host leichter zu prüfen und zu löschen ist.

## Geltungsbereich und Ausnahmen

Alle `ftp://`- und `ftps://`-Verbindungen, auch anonyme, sobald TLS zustande kommt. Zertifikate einer vom System anerkannten Zertifizierungsstelle werden wie bisher ohne Rückfrage akzeptiert.
