# 0002: Englische Oberfläche – Roadmap

Moonlight Commander soll zusätzlich zu Deutsch auf Englisch laufen. Die Sprache richtet sich nach der bevorzugten macOS-Sprache (auch die pro App in den Systemeinstellungen gewählte): Deutsch bei Deutsch, sonst Englisch. Einen eigenen Schalter in der App gibt es nicht.

Der deutsche Text im Code dient als Schlüssel, die englischen Texte liegen in einer `Localizable.strings` im App-Bundle (siehe Slice 1 und ADR-0012).

## Slices

- [x] Slice 1: [Infrastruktur und Hauptfenster](0002-englische-oberflaeche.md) – Lokalisierungs-Baustein, Verpackung, Prüf-Test, Menüleiste, Menüs, Funktionstastenleiste, Panels, Info-Panel, Über-Fenster, ADR
- [x] Slice 2: [Dialoge und Meldungen](0003-englische-oberflaeche-dialoge.md) – Norton-Dialoge, Fortschritt, Suchen, Update-Dialog, Einstellungen, Fehlermeldungen in `MC` und `MCCore`
- [ ] Slice 3: [Editor, Hilfe und Umfeld](0004-englische-oberflaeche-editor-umfeld.md) – Editor/Viewer samt Tastenleiste und Hilfetexten, F1-Hilfe, Dokumenttyp-Namen (`InfoPlist.strings`), Meldungen der Skripte `mc`/`mcedit`, Beispieltext der Datei `ext`, englische README

Bis Slice 3 fertig ist, zeigt die App unter einem englischen System eine Mischung aus Englisch und Deutsch; nicht übersetzte Texte bleiben deutsch, nichts bleibt leer.
