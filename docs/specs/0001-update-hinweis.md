# 0001: Hinweis auf neue Versionen bei GitHub

Status: Ready

## Ziel
Die installierte App merkt, dass bei GitHub ein neueres Release vorliegt, und zeigt einen Hinweis mit Weg zum Download. Die Prüfung läuft nur, wenn der Nutzer das erlaubt hat, oder auf ausdrücklichen Wunsch per Menüpunkt.

## Anforderungen
- R1 (Muss) `MCCore` enthält eine Update-Logik ohne AppKit-Abhängigkeit: Sie fragt `https://api.github.com/repos/patrickdoern/mc/releases/latest` ab (Timeout 10 s, Header `Accept: application/vnd.github+json` und `User-Agent: Moonlight-Commander/<Version>`, sonst nichts Identifizierendes) und liefert Tag (`tag_name`) und Seiten-URL (`html_url`).
- R2 (Muss) Versionsvergleich: Das führende `v` des Tags wird ignoriert, Versionen werden numerisch je Punkt-Segment verglichen (`1.10` > `1.9`, `1.2` = `1.2.0`). Nicht parsebare Tags gelten als „kein Update“. Vorabversionen und Entwürfe (`prerelease`, `draft`) werden ignoriert.
- R3 (Muss) Die eigene Version kommt aus `CFBundleShortVersionString`. Ohne Bundle-Version (Entwicklungsbuild über `swift build`) macht die automatische Prüfung nichts; der Menüpunkt meldet „Version unbekannt (Entwicklungsbuild)“.
- R4 (Muss) Beim ersten Start nach der Installation dieser Version fragt ein Dialog im Norton-Stil (`Dialogs.confirm`, ADR-0006): „Beim Start nach neuen Versionen suchen?“ mit Erklärung, dass dazu `api.github.com` kontaktiert wird und keine persönlichen Daten gesendet werden. Die Antwort wird gespeichert (`Settings.updateCheck`: nicht gefragt / ja / nein); die Frage kommt nie wieder von selbst.
- R5 (Muss) Ist die Prüfung erlaubt, läuft sie beim Start im Hintergrund (nicht blockierend, höchstens einmal je 24 Stunden, Zeitpunkt in `UserDefaults`). Ein Netzfehler wird still ignoriert.
- R6 (Muss) Gibt es ein neueres Release, erscheint ein Dialog im Norton-Stil: „Version X ist verfügbar (installiert: Y).“ mit den Schaltflächen `[< Download-Seite >]` (öffnet `html_url` im Standardbrowser, Enter-Standard) und `[< Später >]`. Pro gefundener Version erscheint der Dialog automatisch nur einmal; die Version wird als „angezeigt“ gespeichert.
- R7 (Muss) Menüpunkt „Nach Updates suchen …“ (ohne Tastenkürzel, ADR-0009) prüft sofort, unabhängig von der gespeicherten Einstellung. Er meldet auch „Du hast die neueste Version.“ und Netzfehler als Fehlermeldung (`Dialogs.show(error:)`).
- R8 (Muss) In den Einstellungen gibt es die Option „Beim Start nach Updates suchen“, die die Antwort aus R4 ändert (Menüeintrag unter den bestehenden Einstellungen in `MainWindowController+Menus.swift`).
- R9 (Muss) Die Datenschutzseite (`website/datenschutz/index.html`) beschreibt die Prüfung: nur nach Zustimmung, Ziel `api.github.com`, GitHub sieht technisch zwangsläufig die IP-Adresse, Abschalten in den Einstellungen. Der Satz „sendet von sich aus nichts ins Netz“ wird entsprechend korrigiert. README und Website-Hinweis werden angepasst, falls sie das Gegenteil behaupten.
- R10 (Muss) Die App lädt nichts herunter und installiert nichts selbst; sie öffnet nur die Release-Seite.
- R11 (Kann) Die Release-Notizen (`body`) erscheinen gekürzt im Dialog.

## Nicht im Umfang
Selbstständiges Herunterladen oder Installieren (Sparkle o. Ä.), Prüfung der Signatur, Beta-Kanal, Telemetrie, Wiederholtes Erinnern an dieselbe Version.

## Betroffene Stellen
- Neu: `Sources/MCCore/UpdateCheck.swift` (Abruf, JSON-Parsing, Versionsvergleich), `Tests/MCCoreTests/UpdateCheckTests.swift`.
- `Sources/MC/Settings.swift` (Einstellung, letzter Prüfzeitpunkt, zuletzt angezeigte Version).
- `Sources/MC/AppDelegate.swift` (Start-Prüfung, Erstfrage).
- `Sources/MC/MainMenu.swift` bzw. `MainWindowController+Menus.swift` (Menüpunkt, Einstellungsoption).
- `Sources/MC/Dialogs.swift` (Update-Dialog, falls `confirm` nicht reicht).
- `website/datenschutz/index.html`, `README.md`, ggf. Startseite der Website.
- Neues ADR (`/adr`): Die App greift nur mit Zustimmung ins Netz (API-Abfrage bei GitHub, kein Auto-Update).

## Relevante ADRs
- ADR-0003 – Verteilung außerhalb des App Stores, deshalb kein eingebauter Update-Mechanismus des Stores.
- ADR-0006 – Dialoge sind eigene Norton-Views, kein `NSAlert`.
- ADR-0009 – Menüpunkt ohne Tastenkürzel oder mit einem, das auf deutscher Tastatur geht.

## Abnahme
- `swift test`: Tests für Versionsvergleich (`1.10` > `1.9`, `v1.2` = `1.2.0`, Müll-Tag), JSON-Parsing (normal, `prerelease`, `draft`, fehlende Felder) mit festen Beispielantworten, ohne Netz.
- Manuell: Version in `scripts/Info.plist` lokal auf `1.1` setzen, `./scripts/bundle.sh`, App starten. Erstfrage erscheint genau einmal; bei „Ja“ erscheint der Dialog „Version 1.2 ist verfügbar“, `Download-Seite` öffnet das Release. Zweiter Start innerhalb von 24 Stunden: kein Dialog. „Nach Updates suchen …“ zeigt den Dialog erneut.
- Manuell: Bei „Nein“ beim Erstdialog gehen beim Start keine Netzanfragen raus (z. B. mit `nettop` oder Little Snitch prüfen); die Einstellung lässt sich später einschalten.
- Manuell: WLAN aus, „Nach Updates suchen …“ zeigt eine verständliche Fehlermeldung, der Start-Check bleibt stumm.
- Datenschutzseite lokal öffnen und den neuen Abschnitt prüfen.

## Offene Fragen
Keine.

## Plan

Checks nach jedem Task: `swift build` und `swift test` (keine Checks-Sektion in CLAUDE.md; abgeleitet aus Package.swift).

- [x] T1: Update-Logik in `MCCore` (R1, R2, R10): `UpdateCheck.swift` mit Abruf, JSON-Parsing, Versionsvergleich, `UpdateCheckTests.swift`. Dateien: `Sources/MCCore/UpdateCheck.swift`, `Tests/MCCoreTests/UpdateCheckTests.swift`.
- [x] T2: Einbindung in die App (R3–R8, R11): Einstellungen (Zustimmung, Zeitpunkt, angezeigte Version), Erstfrage und Start-Prüfung im `AppDelegate`, Update-Dialog, Menüpunkt „Nach Updates suchen …“, Option in den Einstellungen. Dateien: `Sources/MC/Settings.swift`, `AppDelegate.swift`, `Dialogs.swift`, `MainMenu.swift` bzw. `MainWindowController+Menus.swift`.
- [ ] T3: Doku (R9): Datenschutzseite, README und Website-Hinweise korrigieren, neues ADR 0011 samt Eintrag in `docs/adr/README.md`. Dateien: `website/datenschutz/index.html`, `README.md`, `docs/adr/`.
