# 0012: SMB-Freigaben verbinden

Status: Done

## Ziel
Der Nutzer gibt im Verbindungsdialog (⌘K) `smb://server/freigabe` ein und landet im Panel auf der Freigabe, ohne vorher im Finder einzuhängen. Die App hängt die Freigabe über macOS (NetFS) ein, arbeitet dort mit dem lokalen Dateisystem und hängt sie wieder aus, sobald sie nicht mehr gebraucht wird. Ziel-Release 1.6.13.

## Anforderungen
- R1 (Muss) `SMBTarget` in MCCore (neben `FTPTarget`): `isSMB(_:)` erkennt `smb://` ohne Rücksicht auf Groß-/Kleinschreibung. `parse(_:)` nimmt `smb://[user[;domäne]@]host[:port]/freigabe[/pfad]` an. Host und Freigabe sind Pflicht, Prozent-Kodierung wird aufgelöst. Ein Passwort in der Adresse (`user:pw@`) wird abgelehnt (Fehler „Passwörter gehören nicht in die Adresse“), damit es nie in den Verlauf gerät. `displayName` ist `smb://[user@]host/freigabe` ohne Port 445.
- R2 (Muss) ⌘K nimmt SMB-Adressen an. Der Hinweistext im Dialog, `HintLineView`, die Hilfe und der Menüeintrag („SFTP-/FTP-Verbindung …“ → „Netzwerkverbindung …“) nennen SMB. Gelungene Adressen kommen wie bisher in den Verbindungsverlauf. Das ist die Funktion „gemerkte Ziele“, eine eigene Liste gibt es nicht.
- R3 (Muss) Eingehängt wird mit `NetFSMountURLSync`/`NetFSMountURLAsync` (NetFS.framework) im Hintergrund über `runner.run` mit der Anzeige „Verbinde mit … “ und Abbruch. Der Einhängepunkt ist der Standard von macOS (`/Volumes/…`), das System-UI ist ausgeschaltet (`kNAUIOptionKey` = `kNAUIOptionNoUI`). Danach navigiert das Panel mit `LocalFileSystem.shared` auf `<Einhängepunkt>/<pfad>`.
- R4 (Muss) Anmeldung in dieser Reihenfolge: (a) gespeichertes Passwort aus dem Schlüsselbund, Konto `smb://user@host/freigabe` im bestehenden Service, (b) ohne Passwort, sodass Kerberos-Ticket oder Gastzugang greifen, falls der Server sie anbietet, (c) bei einem Anmeldefehler der vorhandene Passwortdialog (`Dialogs.password`, Norton-Stil, ADR-0006) mit „Im Schlüsselbund sichern“. Ohne Nutzer in der Adresse fragt der Dialog zuerst den Nutzernamen ab (Vorgabe: macOS-Kurzname). Schlägt ein gespeichertes Passwort fehl, wird es verworfen und neu gefragt (wie ADR-0008). Passwörter gehen nur über `kNetFSPasswordKey` an NetFS und erscheinen nie in URL, Verlauf, Logs oder Fehlermeldungen.
- R5 (Muss) „Gespeicherte Passwörter …“ zeigt SMB-Konten mit an und kann sie vergessen. Das folgt automatisch aus R4, wenn derselbe Service benutzt wird.
- R6 (Muss) Ist die Freigabe schon eingehängt (Finder, frühere Sitzung), wird der vorhandene Einhängepunkt benutzt (über `getmntinfo`: Typ `smbfs`, gleicher Server und gleiche Freigabe, Groß-/Kleinschreibung egal). Es wird kein zweiter Einhängepunkt angelegt und nicht nach dem Passwort gefragt. Solche Freigaben gelten als „fremd“ und werden von der App nie ausgehängt.
- R7 (Muss) Ein `SMBMounts`-Register in MCCore merkt sich die Einhängepunkte, die die App selbst angelegt hat. Steht kein Panel mehr auf oder unter einem solchen Einhängepunkt (Navigation, ⌘K woandershin, „Schließen“ in „Aktive Verbindungen“), wird er im Hintergrund ausgehängt (`FileManager.unmountVolume` ohne Erzwingen). Gleiches gilt für alle eigenen Einhängepunkte in `applicationWillTerminate`. Ist das Volume belegt (offene Datei, Terminal steht dort), bleibt es ohne Fehlerdialog eingehängt und wird beim nächsten Anlass erneut versucht. Beim Beenden geschieht das ohne Warten über 2 s hinaus.
- R8 (Muss) Die Entscheidung „welche Einhängepunkte sind jetzt frei“ ist eine reine Funktion im Register (Eingabe: Pfade beider Panels, eigene Einhängepunkte; Ausgabe: auszuhängende). Sie berücksichtigt Pfadgrenzen (`/Volumes/a` ist nicht unter `/Volumes/ab`) und den von `realpath` aufgelösten Pfad.
- R9 (Muss) „Aktive Verbindungen“ listet auch Panels auf einer SMB-Freigabe, eigene und fremde, mit `displayName` der Freigabe. „Schließen“ führt das Panel ins Home-Verzeichnis, R7 hängt danach aus, wenn möglich. Die Kopfzeile des Panels bleibt der lokale Pfad.
- R10 (Muss) Panels auf SMB-Freigaben bleiben lokale Panels: FSEvents-Watcher wie bisher (eigene Änderungen kommen sofort), Änderungen anderer Rechner per ⌘R, kein Polling. Festgehalten in einem neuen ADR (siehe Abnahme), das die offene Stelle in ADR-0007 zu Netzlaufwerken beantwortet.
- R11 (Muss) Fehler wie Server nicht erreichbar, Freigabe unbekannt, Anmeldung abgelehnt oder Abbruch erscheinen als verständliche Fehlermeldung mit `displayName`, ohne NetFS-Fehlercodes als einzigen Inhalt. Nach einem Fehler bleibt das Panel, wo es war.
- R12 (Muss) Alle neuen Texte stehen deutsch und englisch (ADR-0014: `localized()` mit einzeiligen Literalen, `en.lproj/Localizable.strings`, `LocalizationTableTests` grün). `README.md`, `README.en.md` (Funktionsliste) und die Website-Funktionsliste beider Sprachen nennen SMB und sagen ausdrücklich, dass es kein eigener SMB-Client ist: Die App hängt die Freigabe über macOS ein (wie der Finder) und zeigt sie dann als lokalen Ordner; Änderungen anderer Rechner erscheinen erst nach ⌘R.
- R13 (Muss) Tests in MCCoreTests: `SMBTarget.parse` (gültige Formen mit Port, Domäne, Pfad, Prozent-Kodierung, Groß-/Kleinschreibung, administrative Freigabe mit `$` wie `c$`; Ablehnung ohne Freigabe, ohne Host, mit Passwort), `displayName`, Abgleich mit Einträgen aus `getmntinfo` (über eine testbare Funktion auf übergebenen Mount-Daten), Register-Entscheidung aus R8 inklusive Pfadgrenzen und fremder Einhängepunkte.
- R14 (Kann) Eine Adresse ohne Freigabe (`smb://server`) listet die Freigaben des Servers (`NetFSMountURLSync` liefert sie nicht ohne UI; nur wenn ein Weg ohne Fremdbibliothek existiert) in einem Norton-Auswahlmenü.

## Nicht im Umfang
- Eigener SMB-Client (libsmb2, Samba) und SMB ohne Einhängen.
- Andere Netzwerkdateisysteme (AFP, NFS, WebDAV), auch wenn NetFS sie könnte.
- Polling oder sonstige Erkennung fremder Änderungen auf Netzlaufwerken.
- Durchsuchen des Netzwerks (Bonjour/NetBIOS) nach Servern.
- Eigene Hotlist-Einträge für SMB: Die Hotlist speichert weiter nur Pfade. Ein Hotlist-Pfad unter `/Volumes/…` funktioniert nur, solange eingehängt ist.
- Erzwungenes Aushängen belegter Volumes.

## Betroffene Stellen
- `Sources/MCCore/SMBTarget.swift` (neu), `Sources/MCCore/SMBMounts.swift` (neu: Einhängen über NetFS, Abgleich mit `getmntinfo`, Register, Aushängen)
- `Package.swift`: `linkerSettings` `.linkedFramework("NetFS")` für MCCore
- `Sources/MC/MainWindowController.swift` (`connect`, Hinweistexte), `Sources/MC/MainWindowController+Actions.swift` (`showConnections`), `Sources/MC/MainWindowController+Menus.swift` (Menüeintrag), `Sources/MC/HintLineView.swift`, `Sources/MC/PanelModel.swift` (Benachrichtigung nach Pfadwechsel für R7), `Sources/MC/AppDelegate.swift` (`applicationWillTerminate`)
- `Sources/MC/Dialogs.swift` (Interaction für Nutzername/Passwort wiederverwenden), `Sources/MC/Keychain.swift` (unverändert, nur neues Kontenformat)
- `Sources/MC/Resources/en.lproj/Localizable.strings`, `README.md`, `README.en.md`, `website/` (DE/EN)
- `Tests/MCCoreTests/SMBTargetTests.swift`, `Tests/MCCoreTests/SMBMountsTests.swift` (neu)
- `docs/adr/0017-smb-ueber-netfs-einhaengen.md` (neu) und `docs/adr/README.md`

## Relevante ADRs
- ADR-0004: Keine neue Fremdbibliothek; NetFS ist Teil von macOS.
- ADR-0006: Passwort- und Nutzerdialog im Norton-Stil statt System-Anmeldedialog, deshalb `kNAUIOptionNoUI`.
- ADR-0007: Live-Aktualisierung nur lokal; offen für Netzlaufwerke, wird durch R10 und das neue ADR beantwortet.
- ADR-0008: Passwörter nur im Schlüsselbund; gilt künftig auch für SMB (neues ADR erweitert den Geltungsbereich).
- ADR-0011: Netzzugriff nur auf ausdrücklichen Wunsch; SMB verbindet nur nach ⌘K, nie beim Start.
- ADR-0014: Texte deutsch im Code, englische Tabelle.

## Abnahme
- `swift build` ohne Warnungen, `swift test` grün.
- ADR-0017 „SMB-Freigaben werden über NetFS eingehängt und als lokale Panels gezeigt“ ist mit `/adr` angelegt: Entscheidung NetFS statt libsmb2 (LGPL bei statischem Linken, Aufwand), eigener Dialog, automatisches Aushängen nur eigener Einhängepunkte, FSEvents + ⌘R auf Netzlaufwerken.
- Manuell gegen eine Windows-Testfreigabe (administrative Freigabe eines Laufwerks, Adresse nur lokal bekannt, nicht im Repo). Schreib- und Löschtests nur in einem eigenen Testordner, nie im Wurzelverzeichnis des Laufwerks.
  - ⌘K `smb://user@host/freigabe` → Passwortdialog → Panel zeigt Inhalt; mit „Im Schlüsselbund sichern“ fragt die zweite Verbindung nicht mehr.
  - Falsches Passwort → erneute Frage, gespeichertes falsches Passwort wird verworfen.
  - F5 von lokal auf die Freigabe und zurück, F8 auf der Freigabe, F3/F4 auf einer Datei dort funktionieren.
  - Panel verlassen → `mount | grep smbfs` zeigt die Freigabe nach wenigen Sekunden nicht mehr. Mit Ctrl-O-Terminal in der Freigabe bleibt sie eingehängt, ohne Fehlermeldung.
  - Im Finder vorher eingehängte Freigabe → ⌘K nutzt sie ohne Passwortfrage, Verlassen hängt sie nicht aus.
  - App beenden mit eigener eingehängter Freigabe → danach nicht mehr eingehängt.
  - Nicht erreichbarer Host und unbekannte Freigabe → verständliche Fehlermeldung, Panel bleibt stehen.
  - Englische Oberfläche: alle neuen Texte englisch.

## Plan
- [x] T1: Kern (R1, R6, R8, R13): `SMBTarget`, `SMBMounts` mit Einhängen über NetFS (ohne UI, Anmeldedaten als Parameter, Anmeldefehler als eigener Fehlerfall), Abgleich mit `getmntinfo`, Register und Freigabe-Entscheidung, Aushängen; NetFS in `Package.swift`; Tests. Dateien: `Sources/MCCore/SMBTarget.swift`, `Sources/MCCore/SMBMounts.swift`, `Package.swift`, `Tests/MCCoreTests/SMBTargetTests.swift`, `Tests/MCCoreTests/SMBMountsTests.swift`.
- [x] T2: Oberfläche (R2–R5, R7, R9, R11): ⌘K-Zweig für SMB mit Anmeldefolge und Schlüsselbund, Aushängen nach Pfadwechsel und beim Beenden, „Aktive Verbindungen“, Menü- und Hinweistexte, Fehlermeldungen. Dateien: `Sources/MC/MainWindowController*.swift`, `Sources/MC/PanelModel.swift`, `Sources/MC/AppDelegate.swift`, `Sources/MC/HintLineView.swift`, `Sources/MC/Dialogs.swift`.
- [x] T3: Texte, Doku, ADR (R10, R12): englische Tabelle, README DE/EN, Website DE/EN, ADR-0017 und ADR-Index.

Danach: Abnahme (manuell in der App gegen eine Testfreigabe).

## Offene Fragen
