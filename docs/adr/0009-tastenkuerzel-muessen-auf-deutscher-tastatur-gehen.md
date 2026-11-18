# ADR-0009: Eigene Tastenkürzel müssen auf einer deutschen Tastatur direkt erreichbar sein

- Status: Accepted
- Datum: 2026-11-18

## Kontext

Der Midnight Commander legt die Hotlist auf Ctrl-\. Auf der deutschen Tastaturbelegung liegt der Backslash auf Option-Shift-7, das Kürzel braucht also Ctrl-Option-Shift-7. Beim Test löste es die Hotlist auch nicht aus.

## Entscheidung

Neue Tastenkürzel werden so gewählt, dass sie auf der deutschen Belegung ohne Umweg über Sondertasten funktionieren. Bekannte mc-Kürzel werden übernommen, wenn sie dort erreichbar sind (F-Tasten, Ctrl-O, Ctrl-S), sonst durch ein gängiges macOS-Kürzel ersetzt (Hotlist: ⌘D). Jedes Kürzel steht im Menü, in der F1-Hilfe und in der README.

## Konsequenzen

Einzelne Kürzel weichen vom Original ab. Wer mc auf einer US-Tastatur gewohnt ist, findet sie über die Menüs.

## Verworfene Alternativen

Ctrl-\ beibehalten: auf der deutschen Belegung kaum erreichbar. Weitere Alternativen: Nicht dokumentiert.

## Geltungsbereich und Ausnahmen

Alle neuen Kürzel im Hauptfenster und im Editor. Nicht dokumentiert: Verhalten auf weiteren Layouts (Schweizer, Österreichische Belegung).
