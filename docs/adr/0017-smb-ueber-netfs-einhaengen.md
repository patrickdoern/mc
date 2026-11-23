# ADR-0017: SMB-Freigaben werden über NetFS eingehängt und als lokale Panels gezeigt

- Status: Accepted
- Datum: 2026-11-23

## Kontext

Windows-Rechner und NAS bieten Dateien meist als SMB-Freigabe an. Bisher musste man sie im Finder einhängen und dann unter `/Volumes/…` öffnen. Über ⌘K soll `smb://server/freigabe` direkt im Panel landen, wie bei SFTP und FTP. macOS kann SMB selbst einhängen (NetFS.framework, wie der Finder), Kerberos, SMB3-Signierung und -Verschlüsselung inklusive.

## Entscheidung

- SMB-Freigaben werden mit NetFS (`NetFSMountURLSync`) am Standard-Einhängepunkt von macOS unter `/Volumes/…` eingehängt. Das Panel arbeitet danach mit dem lokalen Dateisystem auf dem Einhängepunkt; es gibt keinen eigenen SMB-Client.
- Das System-UI von NetFS ist aus (`kNAUIOptionKey` = `kNAUIOptionNoUI`). Nutzername und Passwort fragt der eigene Passwortdialog im Norton-Stil ab (ADR-0006). Angemeldet wird erst mit einem gespeicherten Passwort, dann ohne Passwort (Kerberos oder Gast), dann über den Dialog.
- Passwörter liegen wie bei SFTP nur im Schlüsselbund (ADR-0008), im selben Service `digital.doern.mc.sftp`, Konto `smb://user@host/freigabe`. Ein fehlgeschlagenes gespeichertes Passwort wird verworfen. Passwörter gehen nur über `kNetFSPasswordKey` an NetFS, nie in Adresse, Verlauf, Logs oder Fehlermeldungen. Damit gilt ADR-0008 auch für SMB.
- Die App merkt sich die Einhängepunkte, die sie selbst angelegt hat (`SMBMounts`). Steht kein Panel mehr darauf oder darunter, wird im Hintergrund ausgehängt, ebenso beim Beenden (höchstens 2 s Warten). Ausgehängt wird ohne Erzwingen: Ein belegtes Volume bleibt ohne Fehlermeldung eingehängt und wird beim nächsten Anlass erneut versucht. Schon eingehängte Freigaben (Finder, frühere Sitzung) werden mitbenutzt und nie ausgehängt.
- Panels auf SMB-Freigaben werden wie lokale Panels über FSEvents beobachtet (ADR-0007). Das meldet nur Änderungen dieses Macs. Änderungen anderer Rechner erscheinen nach ⌘R, es gibt kein Polling. Das beantwortet die offene Stelle „Verhalten auf Netzlaufwerken (SMB, NFS)“ in ADR-0007 für SMB.

## Konsequenzen

Keine neue Fremdbibliothek, Anmeldung und Verschlüsselung folgen macOS. Kopieren, Anzeigen, Bearbeiten und das Terminal funktionieren ohne Sonderfälle, weil die Freigabe ein lokaler Ordner ist. Die Kopfzeile zeigt den lokalen Pfad, „Aktive Verbindungen“ nennt die Freigabe. Ein Panel auf einer Freigabe kann veralten, bis der Benutzer ⌘R drückt. Ein belegtes Volume bleibt eingehängt, notfalls bis nach dem Beenden. Schlägt nach dem Einhängen der Wechsel in einen nicht vorhandenen Unterordner fehl, bleibt die Freigabe eingehängt, bis ein Panel sie wieder betritt und verlässt oder die App beendet wird. Hotlist-Pfade unter `/Volumes/…` funktionieren nur, solange eingehängt ist.

## Verworfene Alternativen

- Eigener SMB-Client über libsmb2 oder Samba: LGPL, die nach ADR-0004 statisch gelinkt werden müsste, viel Aufwand, und Kerberos, SMB3-Signierung und -Verschlüsselung müssten selbst nachgezogen werden.
- Der Anmeldedialog von macOS (System-UI von NetFS): bricht den Stil (ADR-0006) und lässt sich nicht mit dem Schlüsselbund-Eintrag der App verbinden.
- Polling auf Netzlaufwerken: Last auf Server und Netz für einen Fall, den ⌘R abdeckt.
- Erzwungenes Aushängen belegter Volumes: Offene Dateien und ein Terminal in der Freigabe würden ohne Rückfrage abgeschnitten.

## Geltungsbereich und Ausnahmen

Alle `smb://`-Verbindungen über ⌘K. Andere Netzwerkdateisysteme (AFP, NFS, WebDAV) sind nicht Gegenstand dieses ADR. Für NFS bleibt die offene Stelle in ADR-0007 bestehen.
