# Moonlight Commander

Nativer Norton-Commander-Klon für macOS (AppKit). Zwei Panels, schnelle Dateioperationen, SFTP, FTP/FTPS und ein mcedit-artiger Editor.

```bash
./scripts/bundle.sh
open build/MC.app --args ~/Downloads ~/projects
```

Bauen: `./scripts/build-libssh2.sh` baut OpenSSL und libssh2 einmalig statisch nach `vendor/` (nur Xcode und Netzwerk nötig). `./scripts/bundle.sh` erzeugt `build/MC.app`, `./scripts/install.sh` installiert sie nach `/Applications/Moonlight Commander.app`. Die App ist eine einzelne Datei ohne Homebrew, läuft ab macOS 14 auf Apple Silicon. Ohne `vendor/` greift `swift build` auf `brew install libssh2` zurück. Tests: `swift test`; mit der Umgebungsvariable `MC_SSH_CONFIG=<Datei>` liest die App SSH-Aliase, Schlüssel und `known_hosts` nur aus dieser Konfiguration statt aus `~/.ssh` (für gefahrlose Tests gegen lokale Server); die SFTP-Tests laufen nur mit `MC_TEST_SSH_DIR` (Ordner mit `clientkey`, sshd auf 127.0.0.1:2222).

## Kommandozeile

`./scripts/install.sh` legt `mc` und `mcedit` nach `~/.local/bin`:

```bash
mc                    # aktuellen Ordner im aktiven Panel öffnen
mc ordner1 ordner2    # linkes und rechtes Panel setzen
mcedit datei.txt      # Datei direkt im Editor öffnen (neue Dateien werden angelegt)
```

Beides funktioniert auch bei laufender App. Ordner lassen sich außerdem aufs Dock-Icon ziehen.

**Finder:** Textdateien lassen sich per Rechtsklick → „Öffnen mit“ → Moonlight Commander im Editor öffnen (die App ist nur als Alternative eingetragen und ersetzt keinen Standard). Über Info → „Öffnen mit“ lässt sie sich für einen Dateityp als Standard festlegen. Ordner, die man aufs Dock-Icon zieht, öffnen sich im aktiven Panel.

## Tasten

| Taste | Aktion |
|---|---|
| Tab | Panel wechseln |
| Enter / Backspace | öffnen / eine Ebene hoch |
| Leertaste, Einfg, ⇧↑↓ | markieren; `+` `-` Muster, `*` umkehren |
| Ctrl-S | Schnellsuche |
| ⌘L / ⇧⌘H / ⌘K | Pfad / Home / SFTP oder FTP verbinden |
| F2 | Benutzermenü (Einträge aus `~/.config/moonlight-commander/menu`, Format wie mc, Makros `%f %d %s %D %F`) |
| F3 / F4 | Anzeigen / Bearbeiten (⇧F4 neue Datei), beides mit Syntax-Highlighting |
| F5 / F6 | Kopieren / Verschieben (⇧F6 Umbenennen) |
| F7 / F8 | Ordner anlegen / Löschen (lokal Papierkorb, ⇧F8 endgültig) |
| F9 / F10 | Menüzeile (Links, Datei, Befehl, Optionen, Rechts) / Beenden; `exit` in der Kommandozeile beendet ebenfalls |
| Tippen | schreibt in die Kommandozeile; Tab vervollständigt Befehle und Dateinamen, Enter führt im Terminal aus (Ordner des aktiven Panels), `cd` wechselt das Panel |
| Ctrl-O | Terminal ein/aus (echte Shell, interaktive Programme wie `vim` und `top` laufen; beim Einblenden wechselt eine untätige Shell in den Ordner des aktiven Panels) |
| ⌘Y | Quick Look für die Datei unter dem Cursor |
| ⌘Enter | Dateiname unter dem Cursor in die Kommandozeile einfügen |
| Ctrl-P / Ctrl-N | Befehlsverlauf |
| ⌘R | Aktualisieren |

Beim Beenden merkt sich die App pro Panel Ordner, Sortierung, Listenformat und Ansicht (Liste, Schnellansicht, Info, Baum) sowie das aktive Panel und stellt sie beim nächsten Start wieder her.

Alle Aktionen stehen auch im Menü (⌥3 bis ⌥8). Editor: F2 Sichern, F3 Block markieren, F4 Ersetzen, F5/F6/F8 Block kopieren/verschieben/löschen, F7 Suchen, Ctrl-Y Zeile löschen, F10/Esc Ende.

SFTP: ⌘K (oder Menü Links/Rechts → SFTP-Verbindung), dann `user@host[:port][/pfad]` oder ein SSH-Alias. Zurück zum lokalen Dateisystem mit ⇧⌘H.

FTP: ebenfalls ⌘K, mit `ftp://[user@]host[:port][/pfad]` (Standard: TLS, wenn der Server es anbietet) oder `ftps://…` (implizites TLS, Port 990). Ohne Nutzer wird anonym angemeldet, Passwörter landen wie bei SFTP optional im Schlüsselbund. Dateien laufen über temporäre Dateien, Symlinks und Zeitstempel setzen gehen nicht. Die FTP-Test läuft nur mit `MC_TEST_FTP_PORT` (anonymer, schreibbarer Server auf 127.0.0.1).

Remote-Terminal: Ctrl-O auf einem SFTP-Panel öffnet eine ssh-Sitzung im Ordner des Panels (je Server eine eigene, das lokale Terminal bleibt daneben bestehen). Beim Passwort-Dialog lässt sich das Passwort im Schlüsselbund sichern (Befehl → Gespeicherte Passwörter zum Vergessen). Mit `MC_SIGN_IDENTITY="Apple Development: …" ./scripts/bundle.sh` signiert, fragt der Schlüsselbund nach einem Neubau nicht erneut.

## Weitere Funktionen

- **Masken:** Beim Kopieren, Verschieben und Umbenennen ist im Ziel eine Maske möglich, z. B. `*.bak` (foo.txt → foo.bak) oder `neu_*` (foo.txt → neu_foo.txt).
- **Archive als Ordner:** zip, tar, tar.gz/bz2/xz/zst, 7z, rar, iso und weitere öffnen mit Enter (schreibgeschützt, Kopieren nach außen und Ansehen gehen).
- **Panelisieren:** Suchergebnisse („Als Panel anzeigen“) oder die Ausgabe eines Befehls (Befehl → Externes Panelisieren) erscheinen als Panel, in dem man kopieren, ansehen und löschen kann.
- **Mehrspaltig:** Listenformat „Kurz“ zeigt 2 bis 3 Spalten.
- **Live-Aktualisierung:** Lokale Panels laden sich selbst neu, sobald sich ihr Verzeichnis von außen ändert; Cursor und Markierungen bleiben erhalten. Bei SFTP, FTP und Archiven bleibt ⌘R.
- **Hintergrund:** Lange Operationen lassen sich im Fortschrittsdialog in den Hintergrund schicken; Status rechts in der Kommandozeile, Abbrechen unter Befehl → Hintergrundaufgaben.
- **Dateizuordnung:** `~/.config/moonlight-commander/ext` legt pro Muster fest, was Enter (`open`), F3 (`view`) und F4 (`edit`) tun; Beispiele stehen in der Datei, nach „Befehl → Dateizuordnung bearbeiten“.
- **Viewer (F3):** F2 Zeilenumbruch, F4 Hex-Ansicht, F5 Gehe zu Zeile, F7 Suche (Regex möglich), F8 Codierung wählen, F9 Vorschau/Quelltext.
- **Markup-Vorschau:** Markdown (`.md`) und HTML (`.html`) erscheinen im Viewer formatiert (Überschriften, Listen, Zitate, Code, Tabellen, Links); F9 schaltet auf den Quelltext. Bei HTML werden Skripte, Stylesheets und Bilder nicht geladen (Bilder erscheinen als `[Bild]`).
- **Editor (F4):** Regex-Suche und -Ersetzen mit `$1`, Codierung wählen, Datei einfügen und Block sichern (Menü Bearbeiten).

## Menüzeile (F9, Pfeiltasten wechseln zwischen den Menüs, Enter wählt, Esc schließt)

- **Links/Rechts:** Dateiliste, Schnellansicht, Info, Baum, Listenformat, Sortierreihenfolge, Filter, SFTP/FTP, Pfad, Anordnen.
- **Datei:** Anzeigen, Bearbeiten, Kopieren, Chmod, Link, symbolischer Link (auch relativ, bearbeitbar), Chown, Umbenennen, Löschen, Gruppenauswahl.
- **Befehl:** Benutzermenü, Verzeichnisbaum, Datei suchen (Name und Inhalt), Verzeichnisse vergleichen (markiert Unterschiede und meldet die Anzahl), Dateien vergleichen (eingebauter Diff im Viewer, funktioniert ohne Xcode; der Cursor im anderen Panel darf auch nur der gleiche Dateiname sein) und optional in FileMerge, Verzeichnisgrößen, Befehlschronik, Chronik angesehener Dateien (die letzten 30 lokalen Dateien aus Viewer und Editor, die ersten neun mit Ziffern 1 bis 9 wieder öffnen), Hotlist (⌘D, die ersten neun Einträge springt man direkt mit den Ziffern 1 bis 9 an), aktive Verbindungen.
- **Optionen:** Konfiguration, Layout, Paneloptionen, Nachfragen, Aussehen (Norton Blau, Dunkel, Hell).

Nicht enthalten: FTP/Shell-Verbindungen, Codierung, Darstellungsbits, Tasten lernen, Virtuelles Dateisystem, Externes Anordnen, Hintergrundaufgaben.

## Verteilen

```bash
MC_SIGN_IDENTITY="Developer ID Application: …" MC_NOTARY_PROFILE=<profil> ./scripts/dist.sh
```

Erzeugt ein signiertes, notarisiertes `build/Moonlight-Commander.dmg`. Das Notary-Profil legst du einmal mit `xcrun notarytool store-credentials` an. Der Mac App Store ist wegen der Sandbox nicht möglich, siehe ADR-0003.

### Auf einen anderen Mac kopieren

`/Applications/Moonlight Commander.app` per `rsync`, `scp` oder USB-Stick kopieren, dann startet sie direkt. Kommt sie per AirDrop, Download oder Cloud, markiert macOS sie als Quarantäne, und Gatekeeper blockiert sie ohne Notarisierung. Dann einmal `xattr -dr com.apple.quarantine "/Applications/Moonlight Commander.app"` ausführen.
