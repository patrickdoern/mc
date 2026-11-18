# ADR-0006: Alle Dialoge, Popups und Fortschrittsanzeigen sind eigene Views im Norton/mc-Stil

- Status: Accepted
- Datum: 2026-11-18

## Kontext

Moonlight Commander soll sich wie Norton Commander und Midnight Commander anfühlen. Standarddialoge von AppKit (`NSAlert`, Sheets, Popup-Menüs) brachen den Stil und ließen sich nicht mit Enter bestätigen, sondern nur per Klick.

## Entscheidung

Dialoge, Auswahl-Popups, Fortschrittsanzeigen und Suchergebnisse bestehen aus eigenen Views (`ClassicDialog`, `ClassicOverlay`, `DropdownView`): eckige Rahmen, Schaltflächen als `[< OK >]`, Farben aus der aktiven Palette. Neue Oberfläche, die den Benutzer etwas fragt oder anzeigt, nutzt diese Bausteine statt `NSAlert` oder Standard-Sheets. Der Fokus startet auf dem ersten Eingabefeld, Enter bestätigt, Esc bricht ab.

## Konsequenzen

Einheitliches Aussehen und volle Tastaturbedienung, dafür mehr eigener Code für Layout und Fokus.

## Verworfene Alternativen

`NSAlert` und Standard-Sheets: runde Ecken, anderer Stil, Bestätigen nur per Klick statt mit Enter. Weitere Alternativen: Nicht dokumentiert.

## Geltungsbereich und Ausnahmen

Alle Dialoge und Popups im Hauptfenster und im Editor. Die macOS-eigenen Systemdialoge (Schlüsselbund-Freigabe, Berechtigungen) lassen sich nicht ersetzen.
