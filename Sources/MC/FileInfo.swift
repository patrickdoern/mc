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
            row("Datei", entry.name),
            row("Pfad", path),
            row("Typ", entry.isSymlink ? "Symbolischer Link" : entry.isDirectory ? "Ordner" : "Datei"),
            row("Größe", size(of: entry, in: model)),
        ]
        guard model.isLocal else {
            lines += [row("Rechte", permissions(entry.permissions)), row("Geändert", entry.modified.map(dateFormatter.string(from:)) ?? ""), row("Server", model.fileSystem.identity)]
            return lines
        }
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return lines }
        if entry.isSymlink, let target = try? LocalFileSystem.shared.readLink(path) { lines.append(row("Ziel", target)) }
        lines += [
            row("Besitzer", getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? String(info.st_uid)),
            row("Gruppe", getgrgid(info.st_gid).map { String(cString: $0.pointee.gr_name) } ?? String(info.st_gid)),
            row("Rechte", permissions(UInt16(info.st_mode & 0o7777))),
            row("Geändert", format(info.st_mtimespec)),
            row("Zugriff", format(info.st_atimespec)),
            row("Statusänderung", format(info.st_ctimespec)),
            row("Inode", String(info.st_ino)),
            row("Links", String(info.st_nlink)),
        ]
        return lines + filesystem(at: path)
    }

    private static func size(of entry: FileEntry, in model: PanelModel) -> String {
        if entry.isDirectory {
            return model.directorySizes[entry.name].map { "\(Formatting.exactSize($0)) (\($0) Bytes)" } ?? "Ordner (Größe mit „Verzeichnisgrößen anzeigen“)"
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
            "Dateisystem",
            row("Gerät", string(from: stats.f_mntfromname)),
            row("Mount-Punkt", string(from: stats.f_mntonname)),
            row("Typ", string(from: stats.f_fstypename)),
            row("Größe", Formatting.exactSize(total)),
            row("Frei", "\(Formatting.exactSize(free))" + (total > 0 ? " (\(Int((Double(free) / Double(total) * 100).rounded())) %)" : "")),
        ]
        if stats.f_files > 0 { lines.append(row("Inodes frei", "\(stats.f_ffree) von \(stats.f_files)")) }
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
