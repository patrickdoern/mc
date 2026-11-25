# 0013: Direktverbindung – Freigeben, finden, koppeln, lesen

Status: Done
Slice: 1/3

## Ziel
Auf Mac B wählt der Nutzer „Freigeben …“ und einen oder mehrere Ordner. Auf Mac A zeigt ⌘K diesen Mac in der Liste; nach Vergleich und Bestätigung eines sechsstelligen Codes zeigt ein Panel auf A die freigegebenen Ordner von B. Man kann darin blättern, Dateien ansehen und sie nach A kopieren. Auf B muss dafür weder SSH noch die Dateifreigabe von macOS eingeschaltet sein. Ziel-Release 1.6.14.

## Anforderungen

### Protokoll und Sicherheit (MCCore)
- R1 (Muss) Eigenes Protokoll „MC-Link“ als reine, testbare Kodierung in MCCore: Rahmen mit 4 Byte Länge (Big Endian), 1 Byte Nachrichtentyp, 4 Byte Anfrage-ID, danach Nutzdaten. Nutzdaten höchstens 1 MiB; ein größerer oder unbekannter Rahmen beendet die Verbindung. Erste Nachricht beider Seiten ist `hello` mit Protokollversion (1) und Anzeigename; bei abweichender Version gibt es auf beiden Seiten eine verständliche Fehlermeldung („Die Gegenstelle hat eine andere Version von Moonlight Commander“).
- R2 (Muss) Anfragen in Slice 1: `list`, `stat`, `statFollowingLinks`, `readLink`, `openRead`, `read` (Block von höchstens 256 KiB), `close`. Antworten: Ergebnis oder `error` mit Text. `FileEntry` wird vollständig übertragen (Name, Typ, Größe, Rechte, alle Zeitstempel, die `FileEntry` kennt, Link-Ziel). Jede andere Anfrage, auch eine schreibende, beantwortet die freigebende Seite mit `error` „Die Freigabe ist nur lesbar“.
- R3 (Muss) Jede Installation hat eine eigene Identität: ein P-256-Schlüssel und ein selbst signiertes Zertifikat, beim ersten Gebrauch erzeugt und im Schlüsselbund abgelegt (eigener Service `digital.doern.mc.link`, nicht unter „Gespeicherte Passwörter“ sichtbar). Das Zertifikat wird ohne Fremdbibliothek erzeugt (DER im Code, Signatur über Security/CryptoKit) und muss sich mit `SecCertificateCreateWithData` lesen lassen.
- R4 (Muss) Transport über Network.framework (`NWListener`, `NWConnection`) mit TLS 1.3 und gegenseitiger Zertifikatsprüfung. Die Prüfung im TLS-Handshake akzeptiert jedes gültig signierte Zertifikat der Gegenseite und merkt sich dessen SHA-256-Fingerabdruck; vertraut wird erst nach der Kopplung (R5). Vor der Kopplung beantwortet die freigebende Seite nur `hello`, alles andere mit Verbindungsende.
- R5 (Muss) Kopplung per Codevergleich bei jeder Verbindung: Der Code ist eine reine Funktion beider Fingerabdrücke (sortiert, SHA-256, sechs Dezimalstellen, angezeigt als `123 456`). Ein Angreifer dazwischen müsste eigene Zertifikate einsetzen und erzeugt damit auf beiden Seiten verschiedene Codes. Die freigebende Seite zeigt „<Name> möchte sich verbinden. Code: 123 456“ mit „Zulassen“ und „Ablehnen“, die verbindende Seite zeigt denselben Code mit „Bitte auf dem anderen Mac bestätigen“ und „Abbrechen“. Ohne Antwort binnen 60 s wird abgebrochen. Solange eine Anfrage offen ist, werden weitere sofort abgewiesen.
- R6 (Muss) Zugriffsprüfung als reine, testbare Funktion auf der freigebenden Seite: Die verbindende Seite sieht `/` als Liste der freigegebenen Ordner (Ordnername; doppelte Namen bekommen ` (2)`, ` (3)` …). Jeder Pfad wird normalisiert, `..` über die Wurzel hinaus abgelehnt und mit `realpath` geprüft, dass das Ziel unter dem freigegebenen Ordner liegt. Symbolische Links, die hinausführen, erscheinen in `list` als Link, `stat` mit Folgen, `openRead` und `list` darauf werden abgelehnt („Außerhalb der Freigabe“). Absolute Pfade des freigebenden Macs gehen nie über die Leitung, auch nicht in Fehlermeldungen.
- R7 (Muss) Pro Freigabe ist höchstens eine verbundene Gegenstelle erlaubt; eine zweite bekommt „Bereits mit <Name> verbunden“.

### Freigebende Seite (MC)
- R8 (Muss) Menü Befehl → „Freigeben …“ öffnet einen Dialog im Norton-Stil (ADR-0006). Er zeigt den Anzeigenamen (Vorgabe: Computername aus den Systemeinstellungen, im Dialog änderbar und gemerkt), die Liste der freigegebenen Ordner (Vorgabe beim ersten Mal: Home; gemerkt in den Einstellungen) mit „Hinzufügen“ (Ordner des aktiven Panels) und „Entfernen“, eine Statuszeile („Wartet auf Verbindung“, „Verbunden mit <Name>“, „<Name> liest <Datei>“) und „Freigabe beenden“. Ohne Ordner lässt sich nicht freigeben.
- R9 (Muss) Gelauscht wird nur, solange der Dialog offen ist: `NWListener` auf einem freien Port, Bonjour-Dienst `_mc-link._tcp` mit TXT-Eintrag `v=1`. Schließen des Dialogs oder Beenden der App beendet Lauschen und bestehende Verbindung sofort. Während der Dialog offen ist, ist das Hauptfenster nicht bedienbar (wie ein LapLink-Server).
- R10 (Muss) `scripts/Info.plist` enthält `NSLocalNetworkUsageDescription` (deutsch, englisch über `en.lproj/InfoPlist.strings`) und `NSBonjourServices` mit `_mc-link._tcp`, damit die Abfrage „Lokales Netzwerk“ von macOS erscheint und Bonjour funktioniert. Lehnt der Nutzer ab oder schlägt das Lauschen fehl, zeigt der Dialog eine verständliche Fehlermeldung mit Hinweis auf Systemeinstellungen → Datenschutz → Lokales Netzwerk.

### Verbindende Seite (MC)
- R11 (Muss) Der Verbindungsdialog (⌘K) sucht, solange er offen ist, per `NWBrowser` nach `_mc-link._tcp` und zeigt gefundene Macs zusätzlich zum Verlauf als `mc://<Name>`, ohne den eigenen. Die Eingabe `mc://<Name>` verbindet über den Bonjour-Namen. Beim Schließen des Dialogs endet die Suche. `mc://`-Ziele kommen in Slice 1 nicht in den Verlauf.
- R12 (Muss) Verbunden wird im Hintergrund über `runner.run` mit „Verbinde mit …“ und Abbruch; danach der Code-Dialog aus R5. Nach „Zulassen“ zeigt das Panel `/` der Freigabe über ein neues `LinkFileSystem: FileSystem` in MCCore. Kopfzeile und „Aktive Verbindungen“ zeigen `mc://<Name>`; „Schließen“ dort trennt die Verbindung und führt ins Home.
- R13 (Muss) Lesend funktioniert alles, was über die `FileSystem`-Schnittstelle liest: Blättern, Sortieren, Filter, Schnellansicht, F3, Info, Dateisuche nach Namen, F5 und Kopieren von der Freigabe auf ein lokales Panel (mit Fortschritt, Abbruch und Hintergrund wie bei SFTP). Schreibversuche (F5/F6 auf die Freigabe, F7, F8, Umbenennen, F4) enden mit „Die Freigabe ist nur lesbar“. Das Panel bleibt dabei stehen.
- R14 (Muss) Lehnt die Gegenseite ab, läuft die Zeit ab, bricht die Verbindung ab oder wird die Freigabe beendet, erscheint eine verständliche Meldung mit `mc://<Name>`; ein Panel auf einer abgebrochenen Verbindung verhält sich wie bei einer abgebrochenen SFTP-Verbindung.
- R15 (Kann) Mehrere `read`-Anfragen gleichzeitig unterwegs (z. B. vier), um im WLAN schneller zu kopieren.

### Doku, Texte, Tests
- R16 (Muss) Neues ADR mit `/adr`: Direktverbindung über eigenes Protokoll mit Network.framework und TLS 1.3, Identität im Schlüsselbund, Kopplung per Codevergleich, Lauschen nur bei offenem Freigabe-Dialog, Bonjour-Suche nur bei offenem Verbindungsdialog, Zugriffsprüfung nur auf der freigebenden Seite. Es erweitert ADR-0011 um eingehende Verbindungen; verworfene Alternativen: nur Bonjour-Suche für SSH/SMB, TLS-PSK aus dem Code (bei sechs Ziffern offline knackbar), dauerhaft lauschender Dienst.
- R17 (Muss) Alle neuen Texte deutsch und englisch (ADR-0014, `LocalizationTableTests` grün). F1-Hilfe, Hinweistext im ⌘K-Dialog und `HintLineView` nennen `mc://` und „Freigeben …“. `README.md`, `README.en.md` und die Website (DE/EN) beschreiben die Funktion, sagen, dass beide Macs Moonlight Commander brauchen, nur im lokalen Netz funktioniert und die Gegenseite in Slice 1 nur lesbar ist, und erwähnen die Abfrage „Lokales Netzwerk“ und ggf. die Firewall.
- R18 (Muss) Tests in MCCoreTests: Rahmen kodieren und dekodieren (auch abgeschnittene, zu große und unbekannte Rahmen), `FileEntry`-Übertragung ohne Verlust, Code aus Fingerabdrücken (gleich auf beiden Seiten, unabhängig von der Reihenfolge, verschieden bei anderem Zertifikat), Zertifikatserzeugung (lesbar, Schlüssel passt), Zugriffsprüfung (Normalisierung, `..`, Links nach außen, doppelte Ordnernamen, keine absoluten Pfade in Fehlern), und ein Durchlauf über 127.0.0.1 mit Server und `LinkFileSystem` in einem Prozess (Kopplung automatisch bestätigt): `list`, `stat`, Datei lesen, Schreiben abgelehnt, Zugriff außerhalb abgelehnt.

## Nicht im Umfang
- Schreiben auf die Freigabe (Slice 2) und gemerkte Kopplung (Slice 3).
- Verbindungen über das lokale Netz hinaus, Eingabe von IP und Port, NAT-Durchdringung, Relais.
- Verbindung zu einem Mac ohne Moonlight Commander.
- Remote-Terminal (Ctrl-O) und Benutzermenü auf der Freigabe, Live-Aktualisierung (⌘R wie bei SFTP).
- Mehrere Gegenstellen gleichzeitig, Lauschen im Hintergrund oder nach Neustart.
- Kompression, Fortsetzen abgebrochener Übertragungen.

## Betroffene Stellen
- Neu in `Sources/MCCore/`: `LinkProtocol.swift` (Rahmen, Nachrichten, `FileEntry`-Kodierung), `LinkIdentity.swift` (Schlüssel, Zertifikat, Fingerabdruck, Code), `LinkShare.swift` (Zugriffsprüfung, Beantworten der Anfragen), `LinkServer.swift` (`NWListener`, Bonjour), `LinkFileSystem.swift` (`NWConnection`, `FileSystem`), `LinkTarget.swift` (`mc://`-Adressen, neben `FTPTarget`/`SMBTarget`)
- `Package.swift`: `Network` und ggf. `CryptoKit` für MCCore
- `Sources/MC/MainWindowController.swift` (`connect`: `mc://`-Zweig, Bonjour im Dialog), `Sources/MC/Dialogs.swift` (Liste mit gefundenen Macs, Code-Dialog), neuer `Sources/MC/ShareDialog.swift`, `Sources/MC/MainWindowController+Menus.swift` (Befehl → Freigeben …), `Sources/MC/MainWindowController+Actions.swift` (`showConnections`), `Sources/MC/HintLineView.swift`, `Sources/MC/Settings.swift` (Ordner, Anzeigename), `Sources/MC/AppDelegate.swift` (Beenden)
- `scripts/Info.plist`, `Sources/MC/Resources/en.lproj/Localizable.strings`, `en.lproj/InfoPlist.strings`, `scripts/bundle.sh` (falls InfoPlist.strings kopiert werden muss)
- `README.md`, `README.en.md`, `website/` (DE/EN)
- `Tests/MCCoreTests/LinkProtocolTests.swift`, `LinkIdentityTests.swift`, `LinkShareTests.swift`, `LinkLoopbackTests.swift` (neu)
- `docs/adr/` neues ADR und Index

## Relevante ADRs
- ADR-0004: Keine neue Fremdbibliothek; Network.framework, Security und CryptoKit gehören zu macOS.
- ADR-0006: Freigabe-, Code- und Fehlerdialoge im Norton-Stil.
- ADR-0008: Geheimnisse nur im Schlüsselbund; gilt hier für den privaten Schlüssel der Identität.
- ADR-0009: Falls „Freigeben …“ ein Kürzel bekommt, muss es auf deutscher Tastatur gehen.
- ADR-0011: Netzzugriff nur auf ausdrücklichen Wunsch; wird durch das neue ADR (R16) um Lauschen und Bonjour ergänzt.
- ADR-0014: Texte deutsch im Code, englische Tabelle.

## Abnahme
- `swift build` ohne Warnungen, `swift test` grün.
- Neues ADR angelegt und im Index.
- Manuell mit zwei Macs im selben Netz, beide mit dem gebündelten und signierten Build (`./scripts/bundle.sh`):
  - B: Befehl → Freigeben …, Ordner wählen → macOS fragt nach „Lokales Netzwerk“, Dialog zeigt „Wartet auf Verbindung“.
  - A: ⌘K zeigt `mc://<Name von B>`; Auswahl → beide zeigen denselben Code; B „Zulassen“ → Panel auf A zeigt die freigegebenen Ordner.
  - Blättern, F3, Schnellansicht, Dateisuche, F5 eines Ordners von B nach A (Inhalt und Zeitstempel stimmen, `diff -r`).
  - F7, F8, F5 nach B → „Die Freigabe ist nur lesbar“.
  - Symlink im freigegebenen Ordner nach `/etc` → nicht betretbar.
  - B „Ablehnen“ → Meldung auf A; 60 s nichts tun → Abbruch auf beiden Seiten.
  - Freigabe auf B beenden, während A ein Panel darauf hat → Meldung auf A wie bei abgebrochener SFTP-Verbindung.
  - Zweiter Mac C versucht sich zu verbinden, während A verbunden ist → abgewiesen.
  - Englische Oberfläche: alle neuen Texte englisch.

## Plan
- [x] T1: Protokoll und Zugriffsprüfung (R1, R2, R6, Teile von R18): Rahmen- und Nachrichtenkodierung, `FileEntry`-Übertragung, Beantworten der Leseanfragen auf freigegebenen Ordnern mit virtueller Wurzel, Pfadprüfung und „nur lesbar“, alles ohne Netz. Dateien: `Sources/MCCore/LinkProtocol.swift`, `Sources/MCCore/LinkShare.swift`, `Tests/MCCoreTests/LinkProtocolTests.swift`, `Tests/MCCoreTests/LinkShareTests.swift`.
- [x] T2: Identität und Code (R3, Codefunktion aus R5, Teile von R18): P-256-Schlüssel und selbst signiertes Zertifikat (DER im Code) im Schlüsselbund-Service `digital.doern.mc.link`, `SecIdentity` für Network.framework, Fingerabdruck, sechsstelliger Code. Dateien: `Sources/MCCore/LinkIdentity.swift`, `Tests/MCCoreTests/LinkIdentityTests.swift`, ggf. `Package.swift`.
- [x] T3: Transport (R4, R5 ohne Oberfläche, R7, R9 Netzteil, R15 falls einfach, Teile von R18): `LinkServer` (`NWListener`, Bonjour `_mc-link._tcp`, TLS 1.3 gegenseitig, Kopplung über Rückruf, 60 s, nur eine offene Anfrage, eine Gegenstelle), `LinkFileSystem: FileSystem` (`NWConnection`, Schreiben → „nur lesbar“), `LinkTarget` (`mc://`), Bonjour-Suche als kleine Klasse; Durchlauftest über 127.0.0.1. Dateien: `Sources/MCCore/LinkServer.swift`, `Sources/MCCore/LinkFileSystem.swift`, `Sources/MCCore/LinkTarget.swift`, `Sources/MCCore/LinkBrowser.swift`, `Package.swift`, `Tests/MCCoreTests/LinkLoopbackTests.swift`, `Tests/MCCoreTests/LinkTargetTests.swift`.
- [x] T4: Oberfläche (R8–R14): Befehl → „Freigeben …“ mit Freigabe-Dialog (Ordner, Anzeigename, Status, gemerkt in `Settings`), Code-Dialoge beider Seiten, ⌘K mit gefundenen Macs und `mc://`-Zweig, „Aktive Verbindungen“, Fehlermeldungen, Beenden in `AppDelegate`, `Info.plist` mit `NSLocalNetworkUsageDescription`/`NSBonjourServices` und `en.lproj/InfoPlist.strings`. Dateien: `Sources/MC/ShareDialog.swift` (neu), `Sources/MC/Dialogs.swift`, `Sources/MC/MainWindowController*.swift`, `Sources/MC/Settings.swift`, `Sources/MC/AppDelegate.swift`, `Sources/MC/HintLineView.swift`, `scripts/Info.plist`, `scripts/bundle.sh`, `Sources/MC/Resources/en.lproj/`.
- [x] T5: Texte, Doku, ADR (R16, R17): englische Tabelle vollständig, F1-Hilfe, README DE/EN, Website DE/EN, neues ADR und Index.

Checks nach jedem Task: `swift build` ohne Warnungen, `swift test` grün.

Danach: Abnahme (manuell mit zwei Macs).

## Offene Fragen
