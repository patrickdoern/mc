# Architecture Decision Records

Entscheidungen, die nicht aus dem Code ablesbar sind. Ein akzeptiertes ADR wird nicht geändert, sondern durch ein neues ersetzt. Neue ADRs mit `/adr` oder aus [TEMPLATE.md](TEMPLATE.md).

| Nr. | Entscheidung | Status |
|---|---|---|
| [0001](0001-appkit-und-swiftpm.md) | Moonlight Commander ist eine native AppKit-App mit eigenem Zeichnen der Panels, gebaut mit SwiftPM | Accepted |
| [0002](0002-sftp-ueber-libssh2.md) | SFTP läuft über libssh2 und liest die Konfiguration über `ssh -G` | Accepted |
| [0003](0003-verteilung-ausserhalb-des-app-stores.md) | Moonlight Commander wird mit Developer ID außerhalb des App Stores verteilt und bringt seine Bibliotheken mit | Accepted |
| [0004](0004-libssh2-und-openssl-statisch-aus-quellen.md) | libssh2 und OpenSSL werden aus geprüften Quellen statisch mit Deployment-Target macOS 14 gebaut | Accepted |
| [0005](0005-terminal-ueber-swiftterm.md) | Das Terminal nutzt SwiftTerm in der letzten Version ohne unstabile Abhängigkeiten | Accepted |
