import Foundation
import MCCore

enum FileInfo {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    static func lines(for model: PanelModel) -> [String] {
        let entry: FileEntry
        let path: String
        if let current = model.currentEntry, !model.isParentRow(model.cursor) {
            entry = current
            path = model.fullPath(of: current.name)
        } else {
            entry = FileEntry(name: PosixPath.name(model.path).isEmpty ? "/" : PosixPath.name(model.path), isDirectory: true)
            path = model.path
        }
        var lines = [
            row(localized("Datei"), entry.name),
            row(localized("Pfad"), path),
            row(localized("Typ"), entry.isSymlink ? localized("Symbolischer Link") : entry.isDirectory ? localized("Ordner") : localized("Datei")),
            row(localized("Größe"), size(of: entry, in: model)),
        ]
        guard model.isLocal else {
            lines += [row(localized("Rechte"), permissions(entry.permissions)), row(localized("Geändert"), entry.modified.map(dateFormatter.string(from:)) ?? ""), row(localized("Server"), model.fileSystem.identity)]
            return lines
        }
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return lines }
        if entry.isSymlink, let target = try? LocalFileSystem.shared.readLink(path) { lines.append(row(localized("Ziel"), target)) }
        lines += [
            row(localized("Besitzer"), getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? String(info.st_uid)),
            row(localized("Gruppe"), getgrgid(info.st_gid).map { String(cString: $0.pointee.gr_name) } ?? String(info.st_gid)),
            row(localized("Rechte"), permissions(UInt16(info.st_mode & 0o7777))),
            row(localized("Geändert"), format(info.st_mtimespec)),
            row(localized("Zugriff"), format(info.st_atimespec)),
            row(localized("Statusänderung"), format(info.st_ctimespec)),
            row(localized("Inode"), String(info.st_ino)),
            row("Links", String(info.st_nlink)),
        ]
        return lines + filesystem(at: path)
    }

    private static func size(of entry: FileEntry, in model: PanelModel) -> String {
        if entry.isDirectory {
            return model.directorySizes[entry.name].map { "\(Formatting.exactSize($0)) (\($0) Bytes)" } ?? localized("Ordner (Größe mit „Verzeichnisgrößen anzeigen“)")
        }
        return "\(Formatting.exactSize(entry.size)) (\(entry.size) Bytes)"
    }

    private static func filesystem(at path: String) -> [String] {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return [] }
        let block = Int64(stats.f_bsize)
        let total = Int64(stats.f_blocks) * block
        let free = Int64(stats.f_bavail) * block
        var lines = [
            "",
            localized("Dateisystem"),
            row(localized("Gerät"), string(from: stats.f_mntfromname)),
            row(localized("Mount-Punkt"), string(from: stats.f_mntonname)),
            row(localized("Typ"), string(from: stats.f_fstypename)),
            row(localized("Größe"), Formatting.exactSize(total)),
            row(localized("Frei"), "\(Formatting.exactSize(free))" + (total > 0 ? " (\(Int((Double(free) / Double(total) * 100).rounded())) %)" : "")),
        ]
        if stats.f_files > 0 { lines.append(row(localized("Inodes frei"), localized("%lld von %lld", Int64(stats.f_ffree), Int64(stats.f_files)))) }
        return lines
    }

    private static func row(_ label: String, _ value: String) -> String {
        label + ":" + String(repeating: " ", count: max(15 - label.count, 1)) + value
    }

    private static func permissions(_ mode: UInt16) -> String {
        "\(Formatting.permissions(mode)) (0\(String(mode & 0o7777, radix: 8)))"
    }

    private static func format(_ time: timespec) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(time.tv_sec)))
    }

    private static func string<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
