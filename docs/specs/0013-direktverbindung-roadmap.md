# 0013: Direktverbindung zwischen zwei Moonlight Commandern – Roadmap

Zwei Moonlight Commander verbinden sich im lokalen Netz direkt miteinander, wie früher LapLink über Kabel: Ein Mac gibt Ordner frei und lauscht, der andere findet ihn per Bonjour, beide vergleichen einen Code, danach zeigt ein Panel die Freigabe des anderen Macs. Die Gegenseite braucht weder SSH noch Dateifreigabe von macOS. Bewusst verworfen wurde „nur Bonjour-Suche für vorhandene SSH- und SMB-Server“, weil das genau diese Einrichtung auf der Gegenseite voraussetzt.

Rahmen für alle Slices:
- Eigenes Protokoll über Network.framework mit TLS 1.3 und gegenseitiger Authentifizierung über selbst erzeugte Zertifikate. Keine neue Fremdbibliothek (ADR-0004).
- Lauschen nur, solange der Freigabe-Dialog offen ist. Bonjour-Suche nur, solange der Verbindungsdialog offen ist (ADR-0011: Netzzugriff nur auf ausdrücklichen Wunsch).
- Zugriff nur unter den gewählten Ordnern; die Prüfung liegt ausschließlich auf der Seite, die freigibt.
- Neue Texte deutsch und englisch (ADR-0014), eigene Norton-Dialoge (ADR-0006), Kürzel auf deutscher Tastatur (ADR-0009), README DE/EN und Website nachziehen.
- Patch-Releases innerhalb von 1.6.

## Slices

- [ ] Slice 1 (1.6.14): [Freigeben, finden, koppeln, lesen](0013-direktverbindung-lesen.md) – Freigabe-Dialog mit gewählten Ordnern, Bonjour, Kopplung per Codevergleich bei jeder Verbindung, Panel auf der Freigabe nur lesend (Blättern, F3, Schnellansicht, F5 von der Freigabe weg)
- [ ] Slice 2 (1.6.15): Schreiben – Häkchen „Schreiben erlauben“ im Freigabe-Dialog (Vorgabe aus), dann F5/F6 auf die Freigabe, F7, F8, Umbenennen, F4 über temporäre Datei, Zeitstempel und Rechte setzen; ohne Häkchen klare Fehlermeldung
- [ ] Slice 3 (1.6.16): Gemerkte Kopplung – nach der ersten Kopplung erkennen sich beide Seiten am Zertifikat wieder und verbinden ohne Code (die freigebende Seite fragt trotzdem nach „Zulassen“, solange nicht anders gewählt); Liste „Gekoppelte Macs“ zum Vergessen; Ziel im Verbindungsverlauf

Slice 2 und 3 sind nur grob beschrieben und bekommen eine eigene Spec, wenn sie an der Reihe sind.
