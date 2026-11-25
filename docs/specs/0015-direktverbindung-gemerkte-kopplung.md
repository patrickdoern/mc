# 0015: Direktverbindung – Gemerkte Kopplung

Status: Ready
Slice: 3/3 (Roadmap: [0013-direktverbindung-roadmap.md](0013-direktverbindung-roadmap.md))

## Ziel
Zwei Macs, die einmal per Code gekoppelt wurden, erkennen sich danach am Zertifikat wieder und verbinden ohne erneuten Codevergleich. Der freigebende Mac fragt weiter „Zulassen?“, außer man hat für diesen Mac „Immer zulassen“ gewählt. Unter Befehl → „Gekoppelte Macs …“ lassen sich Kopplungen vergessen und „Immer zulassen“ zurücknehmen. `mc://`-Ziele kommen in den Verbindungsverlauf. Ziel-Release: mit Slice 1 und 2 zusammen (Version legt Patrick beim Release fest).

## Anforderungen

### Kopplungen speichern (MCCore)
- R1 (Muss) `LinkPairings` in MCCore speichert je gekoppeltem Mac den SHA-256-Fingerabdruck seines Zertifikats (Schlüssel), den zuletzt gesehenen Anzeigenamen und das Merkmal „Immer zulassen“ (Vorgabe aus). Ablage in den Einstellungen (`UserDefaults`, Schlüssel `linkPairings`), für Tests über ein injiziertes `UserDefaults`-Objekt. Fingerabdrücke sind nicht geheim; Geheimnisse (der private Schlüssel) bleiben wie bisher nur im Schlüsselbund (ADR-0008). Dieselbe Liste gilt, egal ob der Mac freigegeben oder sich verbunden hat.
- R2 (Muss) Abfragen als reine Funktionen: Ist ein Fingerabdruck bekannt? Ist er auf „Immer zulassen“? Gibt es einen gespeicherten Eintrag mit demselben Namen, aber anderem Fingerabdruck („Zertifikat geändert“)? Merken, Namen aktualisieren, „Immer zulassen“ setzen und zurücknehmen, vergessen.

### Ablauf der Kopplung (MCCore)
- R3 (Muss) Protokollversion 3. `hello` enthält zusätzlich, ob der Absender den Fingerabdruck der Gegenseite kennt (`knowsPeer`). Beide Seiten kennen die Fingerabdrücke nach dem TLS-Handshake, also vor dem `hello`.
- R4 (Muss) Der Codevergleich entfällt nur, wenn **beide** Seiten einander kennen. Kennt nur eine Seite die andere (z. B. weil die andere die Kopplung vergessen hat), zeigen beide den Code wie beim ersten Mal. So kann sich keine Seite an einem Gerät, das sie nicht kennt, ohne Code anmelden.
- R5 (Muss) Freigebende Seite (`LinkServer`): Das Ereignis `.request` sagt zusätzlich, ob ein Code verglichen werden muss (sonst ohne Code) und ob sich das Zertifikat eines bekannten Namens geändert hat. `decide(_ id:, allow:, always:)`: Mit `always` wird der Mac nach dem Zulassen auf „Immer zulassen“ gesetzt. Ist der Mac bekannt, auf beiden Seiten gekoppelt und auf „Immer zulassen“, wird er ohne `.request` sofort zugelassen; es kommt `.connected` mit dem Hinweis „automatisch zugelassen“. Die 60-s-Frist und die Regel „eine Gegenstelle, eine offene Anfrage“ gelten unverändert.
- R6 (Muss) Verbindende Seite (`LinkFileSystem`): Muss ein Code verglichen werden, wird er wie bisher über `pairing(code)` gemeldet. Sonst meldet sie über einen zweiten Rückruf (oder einen Parameter am vorhandenen), dass auf die Bestätigung der Gegenseite gewartet wird, ohne Code. Ein geänderter Fingerabdruck zu einem bekannten Namen (gleicher Bonjour-Name, anderer Fingerabdruck) wird ebenfalls gemeldet.
- R7 (Muss) Nach einem erfolgreichen Zulassen merken sich **beide** Seiten die Gegenseite (Fingerabdruck und Name) bzw. aktualisieren den Namen. Ein abgelehnter, abgelaufener oder abgebrochener Versuch ändert nichts. Bei geändertem Zertifikat ersetzt das erfolgreiche neue Koppeln den alten Eintrag mit demselben Namen.

### Oberfläche (MC)
- R8 (Muss) Freigabe-Dialog, Anfrage eines unbekannten Macs: wie bisher mit Code, zusätzlich Knopf „Immer zulassen“. Anfrage eines bekannten Macs: „<Name> möchte sich verbinden.“ ohne Code mit „Zulassen“, „Immer zulassen“, „Ablehnen“. Bei geändertem Zertifikat steht vor der Codefrage deutlich: „Das Zertifikat von <Name> hat sich geändert. Nur zulassen, wenn du weißt, warum (z. B. Neuinstallation), und der Code auf beiden Macs gleich ist.“ Statuszeile bei automatischem Zulassen: „Verbunden mit <Name> (automatisch zugelassen)“.
- R9 (Muss) Verbindende Seite: Ohne Code zeigt der Hinweis „Warte auf Bestätigung durch <Name> …“ mit „Abbrechen“ statt des Codes. Bei geändertem Zertifikat steht über dem Code: „Das Zertifikat von <Name> hat sich geändert. Nur fortfahren, wenn du weißt, warum.“
- R10 (Muss) Menü Befehl → „Gekoppelte Macs …“ direkt nach „Gespeicherte Passwörter …“ (Norton-Menü; in der macOS-Menüleiste nur, falls „Gespeicherte Passwörter …“ dort auch steht). Popup wie bei „Gespeicherte Passwörter …“: je Mac „Vergessen: <Name>“ und, falls gesetzt, „Nicht mehr automatisch zulassen: <Name>“; leer: „Keine gekoppelten Macs“.
- R11 (Muss) Erfolgreiche `mc://`-Verbindungen kommen in den Verbindungsverlauf (`sftpHistory`) wie SFTP, FTP und SMB. Im ⌘K-Dialog erscheint ein Mac, der im Verlauf steht und zugleich gefunden wird, nur einmal (an der Stelle des Verlaufs).

### Doku, Texte, Tests
- R12 (Muss) Neues ADR mit `/adr` (nächste Nummer): gemerkte Kopplung nach dem ersten Codevergleich („Trust on first use“ über Zertifikats-Fingerabdrücke), Codevergleich nur entbehrlich, wenn beide Seiten einander kennen, Warnung bei geändertem Zertifikat eines bekannten Namens, „Immer zulassen“ je Mac, Ablage der Fingerabdrücke in den Einstellungen statt im Schlüsselbund (nicht geheim). Ergänzt ADR-0018. Verworfene Alternativen: Kopplung nur einseitig merken (ein vergessener Mac könnte sich sonst an einem fremden Gerät ohne Code anmelden), immer automatisch zulassen, Kopplung über den Namen statt den Fingerabdruck.
- R13 (Muss) Alle neuen Texte deutsch und englisch (ADR-0014, `LocalizationTableTests` grün). README DE/EN, Website DE/EN und F1-Hilfe: einmal koppeln, danach ohne Code; „Immer zulassen“; „Gekoppelte Macs …“; Warnung bei geändertem Zertifikat. Die Datenschutzerklärung (DE/EN) nennt, dass Name und Fingerabdruck gekoppelter Macs lokal in den Einstellungen gespeichert werden.
- R14 (Muss) Tests in MCCoreTests: `LinkPairings` (merken, Name aktualisieren, „Immer zulassen“ setzen/zurücknehmen, vergessen, geänderter Fingerabdruck zu bekanntem Namen, Persistenz über ein Test-`UserDefaults`); Protokoll (`hello` mit `knowsPeer`, Version 3); Durchlauf über 127.0.0.1: erste Verbindung mit Code und beidseitigem Merken, zweite Verbindung ohne Code (Rückruf „warten“ statt Code, `.request` ohne Code), nur eine Seite vergessen → wieder mit Code, „Immer zulassen“ → `.connected` ohne `.request`, geändertes Zertifikat (neue Test-Identität unter demselben Namen) → als geändert gemeldet und mit Code, Ablehnung merkt nichts.

## Nicht im Umfang
- Mehrere Gegenstellen gleichzeitig, Lauschen ohne offenen Freigabe-Dialog.
- Kopplung über das Internet oder mit Macs ohne Moonlight Commander.
- Kopplungen zwischen Macs abgleichen (iCloud o. ä.).
- Schreibrecht je gekoppeltem Mac; „Schreiben erlauben“ bleibt ein Häkchen der Freigabe.

## Betroffene Stellen
- Neu: `Sources/MCCore/LinkPairings.swift`
- `Sources/MCCore/LinkProtocol.swift` (Version 3, `hello` mit `knowsPeer`), `LinkServer.swift` (Kopplungsentscheidung, `.request` mit Code/geändert, `decide(_:allow:always:)`, automatisch zulassen, Merken), `LinkFileSystem.swift` (Entscheidung Code/ohne Code, Rückruf, Merken)
- `Sources/MC/ShareDialog.swift` (Anfragen, „Immer zulassen“, Warnung, Status), `Sources/MC/MainWindowController.swift` (Hinweis ohne Code, Warnung, Verlauf, doppelte Einträge im ⌘K-Dialog), `MainWindowController+Actions.swift` (`showPairedMacs`), `MainWindowController+Menus.swift`, ggf. `MainMenu.swift`, `HintLineView.swift`
- `Sources/MC/Resources/en.lproj/Localizable.strings`, `README.md`, `README.en.md`, `website/` (Startseite, Datenschutz, DE/EN)
- `Tests/MCCoreTests/LinkPairingsTests.swift` (neu), `LinkProtocolTests.swift`, `LinkLoopbackTests.swift`
- `docs/adr/` neues ADR und Index

## Relevante ADRs
- ADR-0018: Grundlage der Direktverbindung und Kopplung per Codevergleich; wird durch das neue ADR ergänzt.
- ADR-0008: Geheimnisse nur im Schlüsselbund; Fingerabdrücke sind keine Geheimnisse und liegen deshalb in den Einstellungen.
- ADR-0011: Netzzugriff nur auf ausdrücklichen Wunsch; „Immer zulassen“ wirkt nur, solange der Freigabe-Dialog offen ist.
- ADR-0006, ADR-0014: Dialoge im Norton-Stil, Texte deutsch und englisch.

## Abnahme
- `swift build` ohne Warnungen, `swift test` grün.
- Neues ADR angelegt und im Index.
- Manuell mit zwei Macs, beide mit derselben neuen Test-DMG:
  - Erste Verbindung A → B: Code auf beiden Seiten, B „Zulassen“. Unter Befehl → „Gekoppelte Macs …“ steht auf beiden Macs der jeweils andere.
  - Zweite Verbindung: A zeigt „Warte auf Bestätigung durch B …“ ohne Code, B fragt ohne Code mit „Zulassen“, „Immer zulassen“, „Ablehnen“.
  - B wählt „Immer zulassen“. Dritte Verbindung: ohne Frage verbunden, Statuszeile „(automatisch zugelassen)“.
  - Auf B „Nicht mehr automatisch zulassen“ → nächste Verbindung fragt wieder (ohne Code).
  - Auf A „Vergessen: B“ → nächste Verbindung wieder mit Code auf beiden Seiten.
  - Ziel `mc://B` steht im ⌘K-Verlauf und erscheint dort nicht doppelt, wenn B gleichzeitig gefunden wird.
  - Auf B den Schlüsselbund-Eintrag „Moonlight Commander“ löschen (neue Identität) → A meldet „Zertifikat geändert“ und zeigt den Code.
  - Englische Oberfläche: alle neuen Texte englisch.

## Plan
- [x] T1: Kopplungen speichern (R1, R2, Teil von R14): `LinkPairings` mit injizierbarem `UserDefaults`, reine Abfragen, Tests. Dateien: `Sources/MCCore/LinkPairings.swift`, `Tests/MCCoreTests/LinkPairingsTests.swift`.
- [x] T2: Ablauf der Kopplung (R3–R7, Teil von R14): Protokoll 3 mit `knowsPeer`, Entscheidung Code/ohne Code auf beiden Seiten, „Immer zulassen“, geändertes Zertifikat, beidseitiges Merken, Durchlauftests. Dateien: `Sources/MCCore/LinkProtocol.swift`, `LinkServer.swift`, `LinkFileSystem.swift`, `Tests/MCCoreTests/LinkProtocolTests.swift`, `LinkLoopbackTests.swift`; nur Kompilier-Anpassungen in `Sources/MC/`.
- [x] T3: Oberfläche (R8–R11): Anfragen mit und ohne Code, „Immer zulassen“, Warnungen, Hinweis „Warte auf Bestätigung“, Befehl → „Gekoppelte Macs …“, Verlauf ohne Doppelte. Dateien: `Sources/MC/ShareDialog.swift`, `Sources/MC/MainWindowController*.swift`, ggf. `MainMenu.swift`, `HintLineView.swift`, `Localizable.strings`.
- [x] T4: Doku und ADR (R12, R13): neues ADR und Index, README DE/EN, Website DE/EN (Startseite, Datenschutz), F1-Hilfe.

Checks nach jedem Task: `swift build` ohne Warnungen, `swift test` grün.

Danach: Abnahme (manuell mit zwei Macs).

## Offene Fragen
