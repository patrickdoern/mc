# ADR-0010: FTP läuft über das System-libcurl, das Remote-Terminal über /usr/bin/ssh

- Status: Superseded by ADR-0015
- Datum: 2026-11-19

## Kontext

Neben SFTP (ADR-0002) soll die App FTP/FTPS sprechen und für SFTP-Panels eine Shell auf dem Server anbieten. Die App soll eine einzelne Datei ohne Homebrew bleiben (ADR-0004).

## Entscheidung

`FTPFileSystem` nutzt das in macOS enthaltene libcurl (Modul `CCurl`, Schlüssel-Wrapper in `shim.h`, weil Swift das variadische `curl_easy_setopt` nicht aufrufen kann). Verzeichnisse kommen per MLSD, ersatzweise per `LIST` im Unix-Format. Dateien werden über temporäre Dateien übertragen, weil libcurl Daten schiebt statt sie anzufordern. `ftp://` versucht TLS (`CURLUSESSL_TRY`), `ftps://` erzwingt implizites TLS. Passwörter folgen ADR-0008. Das Remote-Terminal startet `/usr/bin/ssh -t` mit den über `ssh -G` aufgelösten Einstellungen des Panels; je Server gibt es eine eigene Sitzung.

## Konsequenzen

Kein zusätzlicher Build-Schritt und keine Fremdbibliothek. `ftp://` fällt bei Servern ohne TLS stillschweigend auf Klartext zurück. Große Dateien brauchen temporären Speicherplatz, und es gibt keinen Fortschritt während eines einzelnen Transfers. Befehle aus der Kommandozeile laufen weiter nur lokal; auf dem Server geht es per Ctrl-O.

## Verworfene Alternativen

FISH (Dateizugriff per Shell-Befehle über ssh) wurde nicht gebaut, weil SFTP den Dateizugriff abdeckt. Ein eigener FTP-Client auf Sockets wurde nicht gewählt, weil TLS und die Eigenheiten der Server aufwendig sind.

## Geltungsbereich und Ausnahmen

Alle `ftp://`- und `ftps://`-Verbindungen und das Terminal auf SFTP-Panels.
