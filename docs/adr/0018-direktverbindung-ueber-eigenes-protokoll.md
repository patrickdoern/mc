# ADR-0018: Zwei Moonlight Commander verbinden sich im lokalen Netz direkt über ein eigenes Protokoll mit TLS 1.3 und Kopplung per Codevergleich

- Status: Accepted
- Datum: 2026-11-25

Erweitert ADR-0011 um eingehende Verbindungen. ADR-0011 bleibt unverändert gültig.

## Kontext

Dateien zwischen zwei Macs zu kopieren, ging bisher nur, wenn auf dem anderen Mac SSH („Entfernte Anmeldung“) oder die Dateifreigabe von macOS eingeschaltet und eingerichtet ist. Gewünscht ist eine Verbindung wie bei LapLink: Auf dem einen Mac gibt man Ordner frei, der andere findet ihn und liest darin, ohne Einrichtung auf Systemebene. Bisher hat die App nie gelauscht und nur Verbindungen aufgebaut, die der Nutzer selbst öffnet (ADR-0011). Es gibt keine gemeinsame Stelle, der beide Macs vorab vertrauen, und keine neue Fremdbibliothek ist erlaubt (ADR-0004).

## Entscheidung

- Eigenes Protokoll „MC-Link“ (`LinkProtocol`): Rahmen mit Länge, Nachrichtentyp und Anfrage-ID, Nutzdaten höchstens 1 MiB; ein zu großer oder unbekannter Rahmen beendet die Verbindung. Beide Seiten beginnen mit `hello` (Protokollversion, Anzeigename). Transport über Network.framework (`NWListener`, `NWConnection`, `NWBrowser`) mit TLS 1.3 und gegenseitiger Zertifikatsprüfung.
- Jede Installation hat eine eigene Identität (`LinkIdentity`): ein P-256-Schlüssel im Schlüsselbund (Etikett `digital.doern.mc.link`) und ein selbst signiertes Zertifikat, das ohne Fremdbibliothek als DER im Code erzeugt wird. Im TLS-Handshake wird jedes gültig selbst signierte Zertifikat angenommen und sein SHA-256-Fingerabdruck gemerkt. Vertraut wird erst nach der Kopplung.
- Kopplung per Codevergleich bei jeder Verbindung: Der sechsstellige Code ist eine reine Funktion beider Fingerabdrücke (sortiert, SHA-256). Beide Seiten zeigen ihn an, die freigebende Seite entscheidet mit „Zulassen“ oder „Ablehnen“. Die Entscheidung ist an die Anfrage-ID gebunden. Ohne Antwort binnen 60 s wird abgebrochen. Solange eine Anfrage offen oder eine Gegenstelle verbunden ist, werden weitere abgewiesen. Vor der Kopplung beantwortet die freigebende Seite nur `hello`.
- Gelauscht wird nur, solange der Freigabe-Dialog (Befehl → „Freigeben …“) offen ist: `NWListener` auf einem freien Port mit Bonjour-Dienst `_mc-link._tcp` und `v=1`. Der Dialog ist modal, Schließen oder Beenden der App beendet Lauschen und Verbindung sofort.
- Gesucht wird nur, solange der Verbindungsdialog (⌘K) offen ist. Gefundene Macs erscheinen als `mc://Name`, verbunden wird über den Bonjour-Namen. Ein Verbindungsaufbau ohne Auswahl im Dialog oder ein automatisches Wiederverbinden gibt es nicht.
- Die Zugriffsprüfung (`LinkShare`) läuft nur auf der freigebenden Seite: Sie zeigt eine virtuelle Wurzel mit den freigegebenen Ordnern, normalisiert jeden Pfad, prüft mit `realpath`, dass das Ziel unter einem freigegebenen Ordner liegt, und lehnt Schreibanfragen ab („Die Freigabe ist nur lesbar“). Absolute Pfade der freigebenden Seite gehen nie über die Leitung. Die verbindende Seite (`LinkFileSystem`) gilt als nicht vertrauenswürdig.

## Konsequenzen

- Beide Macs brauchen Moonlight Commander. Ohne Einrichtung auf Systemebene, dafür nur im lokalen Netz; IP-Adressen, Ports oder Verbindungen über das Internet gibt es nicht.
- macOS fragt beim ersten Lauschen oder Suchen nach „Lokales Netzwerk“ (`NSLocalNetworkUsageDescription`, `NSBonjourServices` in `scripts/Info.plist`). Bei eingeschalteter Firewall fragt macOS zusätzlich, ob eingehende Verbindungen erlaubt werden. Lehnt der Nutzer ab, zeigt der Freigabe-Dialog einen Hinweis auf die Systemeinstellungen.
- In Slice 1 ist die Gegenseite nur lesbar. Kopplungen werden nicht gemerkt, der Code ist bei jeder Verbindung zu vergleichen.
- Im Schlüsselbund steht ein Eintrag „Moonlight Commander“ (Schlüssel und Zertifikat). Wird er gelöscht, entsteht beim nächsten Gebrauch eine neue Identität und damit ein anderer Code. Er erscheint nicht unter „Gespeicherte Passwörter“.
- Der alte Datei-Schlüsselbund von macOS verträgt keine gleichzeitige Schlüsselerzeugung aus mehreren Threads. Laden und Anlegen der Identität laufen deshalb unter einer Sperre in `LinkIdentity`.
- `SecItemCopyMatching` und `SecItemDelete` mit `kSecClassIdentity` und `kSecAttrLabel` ignorieren ein nicht passendes Etikett und treffen eine beliebige Identität des Nutzers. Identitäten werden deshalb nie über das Etikett gesucht oder gelöscht, sondern der Schlüssel über das Etikett gesucht, das Zertifikat über den Hash des öffentlichen Schlüssels und die Identität mit `SecIdentityCreateWithCertificate` gebildet. Gelöscht werden nur Schlüssel (über das Etikett) und das konkrete Zertifikat (über die Referenz).
- Jede weitere eingehende Netzfunktion braucht wie hier einen ausdrücklichen Aufruf und eine sichtbare, schließbare Anzeige, solange sie lauscht.

## Verworfene Alternativen

- Nur Bonjour-Suche nach SSH- oder SMB-Diensten anderer Macs: setzt die Einrichtung auf der Gegenseite voraus (Entfernte Anmeldung oder Dateifreigabe, Benutzer und Passwort), genau das soll entfallen.
- TLS mit vorab geteiltem Schlüssel (PSK) aus dem angezeigten Code: Bei sechs Ziffern lässt sich ein mitgeschnittener Handshake offline in kurzer Zeit durchprobieren. Der Codevergleich über die Fingerabdrücke braucht kein Geheimnis im Code.
- Dauerhaft lauschender Dienst (im Hintergrund oder nach Neustart): öffnet einen Port ohne sichtbaren Anlass und bricht das Versprechen aus ADR-0011, dass Netzzugriff nur auf ausdrücklichen Wunsch geschieht.
- Fertige Bibliothek für Transport oder Zertifikate: widerspricht ADR-0004; Network.framework, Security und CryptoKit gehören zu macOS.

## Geltungsbereich und Ausnahmen

Die Direktverbindung über `mc://` und Befehl → „Freigeben …“. SFTP, FTP und SMB sind nicht betroffen. Schreiben auf die Freigabe und gemerkte Kopplungen kommen in späteren Slices und brauchen ggf. ein eigenes ADR.
