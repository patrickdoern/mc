import Foundation

public final class ArchiveFileSystem: FileSystem {
    public let identity: String
    public let archivePath: String
    public var displayName: String { archivePath }
    public var homePath: String { "/" }
    public var exitLocation: ExitLocation? {
        ExitLocation(system: LocalFileSystem.shared, path: PosixPath.parent(archivePath), selecting: PosixPath.name(archivePath))
    }

    private static let bsdtar = "/usr/bin/bsdtar"
    private static let suffixes = [".zip", ".jar", ".war", ".tar", ".tgz", ".tar.gz", ".tbz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz", ".tar.zst", ".7z", ".rar", ".iso", ".cpio", ".xar"]
    private static let linePattern = try! NSRegularExpression(pattern: #"^([\-dlpcbs][rwxsStT\-]{9})[+@.]?\s+\S+\s+.+?\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}:\d{2}|\d{4})\s(.*)$"#)

    private var children: [String: [FileEntry]] = ["/": []]
    private var entries: [String: FileEntry] = [:]
    private var members: [String: String] = [:]
    private var links: [String: String] = [:]

    public static func isArchive(_ name: String) -> Bool {
        let lower = name.lowercased()
        return suffixes.contains { lower.hasSuffix($0) }
    }

    public static func isWritable(_ name: String) -> Bool {
        ArchiveRewriter.formatArguments(for: name) != nil
    }

    public init(path: String) throws {
        archivePath = path
        identity = "archive://" + path
        let listing = try Self.run(["-tvf", path])
        for line in listing.split(separator: "\n") { parse(String(line)) }
    }

    public func list(_ path: String) throws -> [FileEntry] {
        guard let result = children[path] else { throw FileError(localized("%@: Ordner nicht gefunden", path as NSString)) }
        return result
    }

    public func stat(_ path: String) throws -> FileEntry {
        if path == "/" { return FileEntry(name: "/", isDirectory: true) }
        guard let entry = entries[path] else { throw FileError(localized("%@: nicht gefunden", path as NSString)) }
        return entry
    }

    public func readLink(_ path: String) throws -> String {
        guard let target = links[path] else { throw FileError(localized("%@: kein Link", path as NSString)) }
        return target
    }

    public func openReader(_ path: String) throws -> FileReader {
        guard let member = members[path] else { throw FileError(localized("%@: nicht gefunden", path as NSString)) }
        return try ArchiveReader(archive: archivePath, member: member)
    }

    public func makeDirectory(_ path: String) throws { throw readOnly(path) }
    public func removeFile(_ path: String) throws { throw readOnly(path) }
    public func removeDirectory(_ path: String) throws { throw readOnly(path) }
    public func rename(_ from: String, _ to: String) throws { throw readOnly(from) }
    public func makeSymlink(_ path: String, target: String) throws { throw readOnly(path) }
    public func setModified(_ path: String, _ date: Date) throws { throw readOnly(path) }
    public func setPermissions(_ path: String, _ mode: UInt16) throws { throw readOnly(path) }
    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter { throw readOnly(path) }

    private func readOnly(_ path: String) -> FileError {
        FileError(localized("%@ ist ein Archiv und nur lesbar", PosixPath.name(archivePath) as NSString))
    }

    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bsdtar)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FileError(localized("Archiv lässt sich nicht lesen: %@", PosixPath.name(arguments.last ?? "") as NSString)) }
        return String(decoding: data, as: UTF8.self)
    }

    private func parse(_ line: String) {
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = Self.linePattern.firstMatch(in: line, range: range) else { return }
        func group(_ index: Int) -> String { (line as NSString).substring(with: match.range(at: index)) }
        let mode = group(1)
        var name = group(6)
        var target: String?
        if mode.hasPrefix("l"), let arrow = name.range(of: " -> ") {
            target = String(name[arrow.upperBound...])
            name = String(name[..<arrow.lowerBound])
        }
        let isDirectory = mode.hasPrefix("d") || name.hasSuffix("/")
        while name.hasPrefix("./") { name.removeFirst(2) }
        let member = name
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty, name != "." else { return }
        let full = "/" + name
        ensureParents(of: full)
        let entry = FileEntry(
            name: PosixPath.name(full),
            isDirectory: isDirectory,
            isSymlink: target != nil,
            size: Int64(group(2)) ?? 0,
            modified: Self.date(month: group(3), day: group(4), timeOrYear: group(5)),
            permissions: Self.permissions(mode)
        )
        register(entry, at: full)
        members[full] = member
        if let target { links[full] = target }
        if isDirectory, children[full] == nil { children[full] = [] }
    }

    private func ensureParents(of path: String) {
        let parent = PosixPath.parent(path)
        guard parent != "/", entries[parent] == nil else { return }
        ensureParents(of: parent)
        register(FileEntry(name: PosixPath.name(parent), isDirectory: true), at: parent)
        children[parent] = children[parent] ?? []
    }

    private func register(_ entry: FileEntry, at path: String) {
        let parent = PosixPath.parent(path)
        if let existing = children[parent]?.firstIndex(where: { $0.name == entry.name }) {
            children[parent]?[existing] = entry
        } else {
            children[parent, default: []].append(entry)
        }
        entries[path] = entry
    }

    private static func permissions(_ mode: String) -> UInt16 {
        var value: UInt16 = 0
        for (index, character) in mode.dropFirst().enumerated() where character != "-" && character != "S" && character != "T" {
            value |= 1 << UInt16(8 - index)
        }
        return value
    }

    private static func date(month: String, day: String, timeOrYear: String) -> Date? {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard let monthIndex = months.firstIndex(of: month), let dayValue = Int(day) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(month: monthIndex + 1, day: dayValue)
        if timeOrYear.contains(":") {
            let parts = timeOrYear.split(separator: ":").compactMap { Int($0) }
            components.hour = parts[0]
            components.minute = parts[1]
            components.year = calendar.component(.year, from: Date())
            if let date = calendar.date(from: components), date > Date().addingTimeInterval(86_400) {
                components.year! -= 1
            }
        } else {
            components.year = Int(timeOrYear)
        }
        return calendar.date(from: components)
    }
}

private final class ArchiveReader: FileReader {
    private let process = Process()
    private let handle: FileHandle
    private var finished = false

    init(archive: String, member: String) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        let escaped = member.map { "*?[]\\".contains($0) ? "\\\($0)" : String($0) }.joined()
        process.arguments = ["-xOf", archive, escaped]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        handle = output.fileHandleForReading
        try process.run()
    }

    deinit { close() }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        while true {
            let count = Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            if count >= 0 { return count }
            if errno != EINTR { throw FileError(path: "Archiv", errno: errno) }
        }
    }

    func close() {
        guard !finished else { return }
        finished = true
        if process.isRunning { process.terminate() }
        try? handle.close()
    }
}
