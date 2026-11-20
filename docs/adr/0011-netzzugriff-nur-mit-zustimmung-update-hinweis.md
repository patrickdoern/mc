# ADR-0011: Die App greift nur mit Zustimmung ins Netz: Update-Hinweis per Abfrage der GitHub-Release-API, kein Auto-Update

- Status: Accepted
- Datum: 2026-11-20

## Kontext

Die App wird außerhalb des App Stores verteilt (ADR-0003) und bekommt deshalb keine Updates über den Store. Nutzer bemerken neue Versionen nur, wenn sie selbst nachsehen. Gleichzeitig verspricht die Datenschutzerklärung, dass die App nichts von sich aus ins Netz sendet.

## Entscheidung

Die App fragt beim ersten Start einmal, ob sie beim Start nach neuen Versionen suchen darf. Nur bei Zustimmung ruft sie danach automatisch höchstens einmal je 24 Stunden `https://api.github.com/repos/patrickdoern/mc/releases/latest` ab, ohne persönliche Daten, nur mit `User-Agent: Moonlight-Commander/<Version>`. Der Menüpunkt „Nach Updates suchen …“ prüft jederzeit, unabhängig von der Einstellung; die Zustimmung lässt sich in den Einstellungen ändern. Gibt es eine neuere Version, zeigt die App nur einen Hinweis mit Link zur Download-Seite. Sie lädt nichts herunter und installiert nichts selbst. Die Datenschutzerklärung beschreibt die Prüfung.

## Konsequenzen

GitHub sieht bei jeder Abfrage technisch zwangsläufig IP-Adresse und User-Agent. Die Aussage „sendet von sich aus nichts ins Netz“ entfällt und wird durch die Zustimmung ersetzt. Das Update bleibt ein manueller Schritt des Nutzers. Jede weitere Netzfunktion braucht ebenfalls Zustimmung oder einen ausdrücklichen Aufruf.

## Verworfene Alternativen

Sparkle (zusätzliche Abhängigkeit, eigene Installationslogik, Signaturschlüssel für Updates), automatische Prüfung ohne Rückfrage (bricht das Datenschutzversprechen), nur manuelle Prüfung (neue Versionen bleiben meist unbemerkt).

## Geltungsbereich und Ausnahmen

Die Update-Prüfung der App. Verbindungen zu Servern, die der Nutzer selbst öffnet (SFTP, FTP), sind davon unabhängig.
