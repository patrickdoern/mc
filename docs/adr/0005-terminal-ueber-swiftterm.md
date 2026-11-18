# ADR-0005: Das Terminal nutzt SwiftTerm in der letzten Version ohne unstabile Abhängigkeiten

- Status: Accepted
- Datum: 2026-11-18

## Kontext

Interaktive Programme in der Kommandozeile (`vim`, `top`, `ssh`) brauchen einen Terminal-Emulator mit Pseudoterminal. Einen eigenen zu schreiben, wäre unverhältnismäßig.

## Entscheidung

Das eingebettete Terminal (Ctrl-O) nutzt die Bibliothek SwiftTerm (MIT) mit `LocalProcessTerminalView`. Die Version ist exakt auf 1.5.1 gepinnt. Ab 1.6.0 hängt SwiftTerm von einem Branch-Paket (`swift-subprocess`) ab, das SwiftPM für stabile Versionen nicht auflöst. Befehle aus der Kommandozeile laufen in dieser Shell statt in einem Ausgabefenster.

## Konsequenzen

Eine Fremdabhängigkeit mit eigenem Update-Pfad. Ein Wechsel auf neuere SwiftTerm-Versionen ist erst möglich, wenn diese Abhängigkeit stabil ist oder wir sie ebenfalls pinnen.

## Verworfene Alternativen

Eigener Emulator (Aufwand), Ausgabefenster ohne Eingabe (keine interaktiven Programme), Öffnen von Terminal.app (bricht den Arbeitsfluss).

## Geltungsbereich und Ausnahmen

Das gesamte Terminal-Feature.
