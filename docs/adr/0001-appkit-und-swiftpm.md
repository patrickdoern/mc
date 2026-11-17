# ADR-0001: macOS Commander ist eine native AppKit-App mit eigenem Zeichnen der Panels, gebaut mit SwiftPM

- Status: Accepted
- Datum: 2026-11-17

## Kontext

Der Midnight Commander im Terminal ist für große Verzeichnisse und Dateioperationen zu langsam. macOS Commander soll Dateioperationen, SFTP und einen mcedit-artigen Editor nativ auf macOS liefern.

## Entscheidung

Oberfläche in AppKit, Panels als eigene `NSView`, die nur sichtbare Zeilen zeichnet. Kern (Dateisysteme, Operationen) liegt in der Bibliothek `MCCore` ohne UI-Abhängigkeit und wird per SwiftPM gebaut; die `.app` entsteht über `scripts/bundle.sh`.

## Konsequenzen

Dateioperationen laufen auf Hintergrund-Queues, lokales Kopieren nutzt `copyfile` mit APFS-Clone. Die UI lässt sich nicht per SwiftUI erweitern. Der Kern ist ohne UI testbar.

## Verworfene Alternativen

SwiftUI (zu wenig Kontrolle über Tastatur und Zeichnen), `NSTableView` (Tastatursemantik von Norton Commander nur mit Gegenarbeit), Xcode-Projekt über xcodegen (für ein einzelnes Package unnötig).

## Geltungsbereich und Ausnahmen

Gesamtes Projekt.
