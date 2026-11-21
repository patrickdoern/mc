import Foundation

/// Logik für „In Archiv packen“, die ohne Oberfläche testbar ist.
public enum ArchivePacking {
    /// Vorgabe für den Archivnamen: ein Eintrag nach dessen Namen, sonst nach dem aktuellen Ordner.
    public static func defaultName(names: [String], directory: String) -> String {
        var base = names.count == 1 ? names[0] : PosixPath.name(directory)
        if base.isEmpty { base = localized("Archiv") }
        return base + ".zip"
    }

    /// Prüft Endung und Ziel; wirft eine verständliche Meldung, ohne etwas anzulegen.
    public static func validate(archivePath: String, on system: FileSystem) throws {
        guard system is LocalFileSystem else { throw FileError(localized("Archive lassen sich nur lokal anlegen")) }
        guard ArchiveFileSystem.isWritable(PosixPath.name(archivePath)) else {
            throw FileError(localized("„%@“ hat keine Archiv-Endung, die sich beschreiben lässt (zip, tar, tar.gz, tar.bz2, tar.xz, 7z)", PosixPath.name(archivePath) as NSString))
        }
    }

    /// Zuordnung der Quellen auf Pfade im Archiv. Das Archiv selbst wird ausgelassen, wenn es in `sourceDirectory` liegt.
    public static func transfers(names: [String], sourceDirectory: String, archivePath: String?) -> [Transfer] {
        names.compactMap { name in
            let source = PosixPath.join(sourceDirectory, name)
            if source == archivePath { return nil }
            return Transfer(source: source, destination: "/" + PosixPath.name(name))
        }
    }
}
