# ADR-0013: Die Website läuft auf GitHub Pages unter moonlight-commander.org, mit je einer statischen Seite pro Sprache

- Status: Accepted
- Datum: 2026-11-21

## Kontext

Die Website (`website/`, statisches HTML und CSS) lag zuerst auf dem eigenen Server `janus` und wurde mit einem Skript per `rsync` dorthin kopiert, unter `moonlight-commander.de`. Die App soll jetzt auch Englisch sprechen (ADR-0012), die Website soll beide Sprachen anbieten. Der Quellcode und die Releases (DMG) liegen ohnehin bei GitHub.

## Entscheidung

- Die Website wird über GitHub Pages ausgeliefert, unter der Domain `moonlight-commander.org` (Apex-Domain mit vier `A`- und vier `AAAA`-Einträgen auf GitHub; `www` als `CNAME` auf `patrickdoern.github.io`, GitHub leitet `www` auf die Apex-Domain um).
- Veröffentlicht wird über den Workflow `.github/workflows/pages.yml` (getrennte Jobs `build` und `deploy`, Ordner `website`), ausgelöst bei Push auf `main` mit Änderungen unter `website/**` oder manuell. Die Pages-Quelle ist „GitHub Actions“, weil Pages sonst nur das Wurzelverzeichnis oder `/docs` ausliefern kann, nicht `/website`. Es gibt keine `CNAME`-Datei im Repo, die Domain steht in den Pages-Einstellungen.
- Jede Sprache hat eigene statische Seiten: Deutsch im Wurzelverzeichnis (`/`, `/impressum`, `/datenschutz`, `/lizenzen`), Englisch unter `/en/` (`/en/legal-notice/`, `/en/privacy/`, `/en/licenses/`). Ein Umschalter „Deutsch | English“ oben rechts verlinkt auf die jeweilige Gegenseite; `canonical` und `hreflang` sind gesetzt. Es gibt keine Cookies und keine Spracherkennung oder Weiterleitung per JavaScript.
- Impressum und Datenschutzerklärung gibt es auf Englisch als Übersetzung, gekennzeichnet; verbindlich ist die deutsche Fassung.
- Die Reichweitenmessung bleibt Matomo auf dem eigenen Server (`metrics.doern.eu`, ohne Cookies). Die Datenschutzerklärung nennt GitHub Pages als Hosting.
- Die alte Domain `moonlight-commander.de` leitet auf `janus` per 301 auf `moonlight-commander.org` um, weil Pages nur eine Domain bedient. Das gilt auch für die Links in App-Versionen bis 1.3.

## Konsequenzen

Quellcode und Hosting liegen an einem Ort, ein Push auf `main` mit Änderungen unter `website/` veröffentlicht die Seite. Der Server `janus` und das Deploy-Skript entfallen für die Website, `janus` bleibt für die Weiterleitung der alten Domain nötig. Die Website hängt damit an GitHub: Besucher verbinden sich mit GitHub (steht in der Datenschutzerklärung), und GitHub Pages bei einem privaten Repo bräuchte einen bezahlten Plan. Die Änderung eines `DNS`-Eintrags wirkt wegen der Resolver-Caches zeitverzögert, und das HTTPS-Zertifikat stellt GitHub erst danach aus. Jede Änderung an einer Seite muss in beiden Sprachen nachgezogen werden.

## Verworfene Alternativen

- Weiter auf dem eigenen Server `janus` (Caddy und `rsync`-Skript `scripts/deploy-website.sh`, inzwischen entfernt): Gründe nicht dokumentiert.
- Eine Seite mit Sprachumschaltung per JavaScript: Die zweite Sprache wäre ohne JavaScript nicht erreichbar und nicht einzeln verlinkbar.
- Cloudflare Pages wie bei `status.doern.eu`: Nicht gewählt; `status.doern.eu` bleibt dort und ist nicht Gegenstand dieses ADR. Weitere Gründe nicht dokumentiert.

## Geltungsbereich und Ausnahmen

`website/`, die Domain `moonlight-commander.org`, der Workflow `pages.yml` und die Datenschutzseiten. Nicht dokumentiert: Ob die in der Datenschutzerklärung genannte Zertifizierung von GitHub, Inc. nach dem EU-U.S. Data Privacy Framework geprüft wurde.
