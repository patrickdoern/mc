# ADR-0019: Gekoppelte Macs werden am Zertifikats-Fingerabdruck wiedererkannt; der Codevergleich entfällt nur, wenn beide Seiten einander kennen

- Status: Accepted
- Datum: 2026-11-25

Ergänzt ADR-0018 um gemerkte Kopplungen. ADR-0018 bleibt im Übrigen gültig.

## Kontext

Nach ADR-0018 vergleichen beide Macs bei jeder Verbindung einen sechsstelligen Code. Für zwei Macs, die regelmäßig miteinander arbeiten, ist das lästig und lädt dazu ein, den Code ungeprüft zu bestätigen. Die Identität jeder Installation steht ohnehin fest (Zertifikat im Schlüsselbund), und beide Seiten kennen den Fingerabdruck der Gegenseite nach dem TLS-Handshake.

## Entscheidung

- Trust on first use über Zertifikats-Fingerabdrücke: Nach dem ersten erfolgreichen Codevergleich merken sich beide Macs die Gegenseite (`LinkPairings`) mit SHA-256-Fingerabdruck ihres Zertifikats als Schlüssel, zuletzt gesehenem Namen und dem Merkmal „Immer zulassen“ (Vorgabe aus). Gemerkt wird nur nach erfolgreichem Zulassen, auf der freigebenden Seite beim Zulassen, auf der verbindenden beim `done`, dort unter dem Bonjour-Namen. Abgelehnte, abgelaufene oder abgebrochene Versuche ändern nichts. Dieselbe Liste gilt für beide Rollen.
- Protokoll 3: `hello` trägt `knowsPeer`, ob der Absender den Fingerabdruck der Gegenseite kennt. Der Codevergleich entfällt nur, wenn beide Seiten einander kennen; beide entscheiden aus denselben zwei Angaben und kommen so zum selben Ergebnis. Auch ohne Code fragt die freigebende Seite „Zulassen?“.
- Taucht ein bekannter Name mit anderem Fingerabdruck auf, warnen beide Seiten deutlich vor dem geänderten Zertifikat und verlangen den Codevergleich. Erfolgreiches neues Koppeln ersetzt den alten Eintrag mit diesem Namen.
- „Immer zulassen“ gilt je Mac und wird beim Zulassen gewählt. Es wirkt nur bei beidseitiger Kopplung und nur, solange der Freigabe-Dialog offen ist (ADR-0011, ADR-0018); die Statuszeile meldet „(automatisch zugelassen)“. Unter Befehl → „Gekoppelte Macs …“ lassen sich Kopplungen vergessen und „Immer zulassen“ zurücknehmen.
- Fingerabdrücke und Namen liegen in den Einstellungen (`UserDefaults`, Schlüssel `linkPairings`), nicht im Schlüsselbund: Sie sind nicht geheim. Geheim ist nur der private Schlüssel, und der bleibt im Schlüsselbund (ADR-0008, ADR-0018).
- Die Protokollversion wird bei jeder Formatänderung erhöht, ältere Gegenstellen werden mit „andere Version“ abgewiesen. Der Bonjour-Eintrag `v` trägt die aktuelle Version (derzeit 3), die Angabe `v=1` in ADR-0018 ist damit überholt.

## Konsequenzen

- Gekoppelte Macs verbinden ohne Code. Ein Angreifer bei der allerersten Verbindung bliebe unerkannt, wenn der Code nicht verglichen wird, wie bei SSH-Hostkeys und ADR-0016.
- Vergisst eine Seite die Kopplung, zeigen beim nächsten Mal wieder beide den Code.
- Wird der Schlüsselbund-Eintrag „Moonlight Commander“ gelöscht, entsteht eine neue Identität; der andere Mac meldet dann ein geändertes Zertifikat, bis neu gekoppelt ist.
- Ein umbenannter Mac bleibt am Fingerabdruck erkannt, sein Name wird beim nächsten Zulassen aktualisiert.
- Macs mit älterer Version verbinden sich nicht mehr mit Macs ab Protokoll 3.

## Verworfene Alternativen

- Kopplung nur einseitig merken: Hat ein Mac die Kopplung vergessen, könnte er sich sonst ohne Code an einem Gerät anmelden, das er selbst nicht mehr prüfen kann, also auch an einem fremden.
- Gekoppelte Macs immer automatisch zulassen: Die freigebende Seite verlöre die Kontrolle, wer gerade zugreift; deshalb nur auf ausdrücklichen Wunsch je Mac.
- Kopplung über den Namen statt den Fingerabdruck: Der Bonjour-Name ist frei wählbar und lässt sich von jedem Gerät im Netz vortäuschen.

## Geltungsbereich und Ausnahmen

Die Direktverbindung über `mc://` und Befehl → „Freigeben …“. SFTP, FTP und SMB sind nicht betroffen. Mehrere Gegenstellen gleichzeitig, Lauschen ohne offenen Freigabe-Dialog und ein Abgleich der Kopplungen zwischen Macs gibt es nicht.
