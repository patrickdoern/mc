# Architecture Decision Records

Entscheidungen, die nicht aus dem Code ablesbar sind. Ein akzeptiertes ADR wird nicht geändert, sondern durch ein neues ersetzt. Neue ADRs mit `/adr` oder aus [TEMPLATE.md](TEMPLATE.md).

| Nr. | Entscheidung | Status |
|---|---|---|
| [0001](0001-appkit-und-swiftpm.md) | macOS Commander ist eine native AppKit-App mit eigenem Zeichnen der Panels, gebaut mit SwiftPM | Accepted |
| [0002](0002-sftp-ueber-libssh2.md) | SFTP läuft über libssh2 und liest die Konfiguration über `ssh -G` | Accepted |
