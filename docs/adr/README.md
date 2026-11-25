# Architecture Decision Records

Entscheidungen, die nicht aus dem Code ablesbar sind. Ein akzeptiertes ADR wird nicht geändert, sondern durch ein neues ersetzt. Neue ADRs mit `/adr` oder aus [TEMPLATE.md](TEMPLATE.md).

| Nr. | Entscheidung | Status |
|---|---|---|
| [0001](0001-appkit-und-swiftpm.md) | Moonlight Commander ist eine native AppKit-App mit eigenem Zeichnen der Panels, gebaut mit SwiftPM | Accepted |
| [0002](0002-sftp-ueber-libssh2.md) | SFTP läuft über libssh2 und liest die Konfiguration über `ssh -G` | Accepted |
| [0003](0003-verteilung-ausserhalb-des-app-stores.md) | Moonlight Commander wird mit Developer ID außerhalb des App Stores verteilt und bringt seine Bibliotheken mit | Accepted |
| [0004](0004-libssh2-und-openssl-statisch-aus-quellen.md) | libssh2 und OpenSSL werden aus geprüften Quellen statisch mit Deployment-Target macOS 14 gebaut | Accepted |
| [0005](0005-terminal-ueber-swiftterm.md) | Das Terminal nutzt SwiftTerm in der letzten Version ohne unstabile Abhängigkeiten | Accepted |
| [0006](0006-dialoge-und-popups-im-norton-stil.md) | Alle Dialoge, Popups und Fortschrittsanzeigen sind eigene Views im Norton/mc-Stil | Accepted |
| [0007](0007-live-aktualisierung-nur-fuer-lokale-panels.md) | Nur lokale Panels aktualisieren sich selbst, über FSEvents | Accepted |
| [0008](0008-sftp-passwoerter-im-schluesselbund.md) | SFTP-Passwörter liegen ausschließlich im macOS-Schlüsselbund | Accepted |
| [0009](0009-tastenkuerzel-muessen-auf-deutscher-tastatur-gehen.md) | Eigene Tastenkürzel müssen auf einer deutschen Tastatur direkt erreichbar sein | Accepted |
| [0010](0010-ftp-ueber-libcurl-remote-terminal-ueber-ssh.md) | FTP läuft über das System-libcurl, das Remote-Terminal über /usr/bin/ssh | Superseded by ADR-0015 |
| [0011](0011-netzzugriff-nur-mit-zustimmung-update-hinweis.md) | Die App greift nur mit Zustimmung ins Netz: Update-Hinweis per Abfrage der GitHub-Release-API, kein Auto-Update | Accepted |
| [0012](0012-englische-oberflaeche-ueber-deutsche-schluessel.md) | Texte der App stehen auf Deutsch im Code und werden über `localized` mit englischer Tabelle und Systemsprache übersetzt | Superseded by ADR-0014 |
| [0013](0013-website-auf-github-pages-zweisprachig.md) | Die Website läuft auf GitHub Pages unter moonlight-commander.org, mit je einer statischen Seite pro Sprache | Accepted |
| [0014](0014-sprache-nach-system-und-in-der-app-waehlbar.md) | Texte der App stehen auf Deutsch im Code und werden über `localized` mit englischer Tabelle übersetzt; die Sprache folgt dem System und lässt sich in der App überschreiben | Accepted |
| [0015](0015-ftp-anmeldung-nur-mit-tls-oder-zustimmung.md) | FTP läuft über das System-libcurl; Anmeldungen mit Passwort laufen nur über TLS oder nach ausdrücklicher Zustimmung im Klartext | Accepted |
| [0016](0016-ftp-zertifikate-beim-ersten-verbinden-bestaetigen.md) | FTP-Zertifikate ohne bekannte Zertifizierungsstelle werden beim ersten Verbinden bestätigt und gespeichert | Accepted |
| [0017](0017-smb-ueber-netfs-einhaengen.md) | SMB-Freigaben werden über NetFS eingehängt und als lokale Panels gezeigt | Accepted |
| [0018](0018-direktverbindung-ueber-eigenes-protokoll.md) | Zwei Moonlight Commander verbinden sich im lokalen Netz direkt über ein eigenes Protokoll mit TLS 1.3 und Kopplung per Codevergleich | Accepted |
