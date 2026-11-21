import Foundation

public final class ArchiveFileSystem: FileSystem {
    public let identity: String
    public let archivePath: String
    public var displayName: String { archivePath }
    public var homePath: String { "/" }
    public var exitLocation: ExitLocation? {
        ExitLocation(system: LocalFileSystem.shared, path: PosixPath.parent(archivePath), selecting: PosixPath.name(archivePath))
    }

    private static let suffixes = [".zip", ".jar", ".war", ".tar", ".tgz", ".tar.gz", ".tbz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz", ".tar.zst", ".7z", ".rar", ".iso", ".cpio", ".xar"]
    private static let linePattern = try! NSRegularExpression(pattern: #"^([\-dlpcbs][rwxsStT\-]{9})[+@.]?\s+\S+\s+.+?\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}:\d{2}|\d{4})\s(.*)$"#)

    private let writable: Bool
    private let lock = NSLock()
    private var model = Model()
    private var snapshot: Model?
    private var depth = 0
    private var changeCount = 0
    private var stage = ""
    private var stagedCount = 0

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
        writable = Self.isWritable(PosixPath.name(path))
        try load()
    }

    deinit { try? FileManager.default.removeItem(atPath: stage) }

    public var hasPendingChanges: Bool { locked { depth > 0 && changeCount > 0 } }

    public func beginTransaction() {
        locked {
            guard writable else { return }
            if depth == 0 { start() }
            depth += 1
        }
    }

    public func commitTransaction() throws {
        try commit()
    }

    public func rollbackTransaction() {
        locked { discard() }
    }

    public func list(_ path: String) throws -> [FileEntry] {
        try locked {
            guard let result = model.children[path] else { throw FileError(localized("%@: Ordner nicht gefunden", path as NSString)) }
            return result
        }
    }

    public func stat(_ path: String) throws -> FileEntry {
        if path == "/" { return FileEntry(name: "/", isDirectory: true) }
        return try locked {
            guard let entry = model.entries[path] else { throw FileError(localized("%@: nicht gefunden", path as NSString)) }
            return entry
        }
    }

    public func readLink(_ path: String) throws -> String {
        try locked {
            guard let target = model.links[path] else { throw FileError(localized("%@: kein Link", path as NSString)) }
            return target
        }
    }

    public func openReader(_ path: String) throws -> FileReader {
        let origin = locked { model.origins[path] }
        switch origin {
        case .archive(_, let member): return try ArchiveReader(archive: archivePath, member: member)
        case .staged(let file): return try LocalFileSystem.shared.openReader(file)
        default: throw FileError(localized("%@: nicht gefunden", path as NSString))
        }
    }

    public func makeDirectory(_ path: String) throws {
        try modify(path) {
            try checkTarget(path, replaceable: false)
            stagedCount += 1
            let folder = try stageFolder() + "/n\(stagedCount)"
            guard mkdir(folder, 0o755) == 0 else { throw FileError(path: path, errno: errno) }
            insert(FileEntry(name: PosixPath.name(path), isDirectory: true, modified: Date(), permissions: 0o755), at: path, origin: .staged(folder))
        }
    }

    public func removeFile(_ path: String) throws {
        try modify(path) {
            guard let entry = model.entries[path] else { throw FileError(path: path, errno: ENOENT) }
            guard !entry.isDirectory else { throw FileError(path: path, errno: EISDIR) }
            removeNode(path)
        }
    }

    public func removeDirectory(_ path: String) throws {
        try modify(path) {
            guard let entry = model.entries[path] else { throw FileError(path: path, errno: ENOENT) }
            guard entry.isDirectory else { throw FileError(path: path, errno: ENOTDIR) }
            guard model.children[path]?.isEmpty ?? true else { throw FileError(path: path, errno: ENOTEMPTY) }
            removeNode(path)
        }
    }

    public func rename(_ from: String, _ to: String) throws {
        try modify(from) {
            guard let entry = model.entries[from] else { throw FileError(path: from, errno: ENOENT) }
            guard from != to else { return }
            guard !to.hasPrefix(from + "/") else { throw FileError(path: from, errno: EINVAL) }
            try checkTarget(to, replaceable: false)
            let moved = entry.copy(name: PosixPath.name(to))
            model.children[PosixPath.parent(from)]?.removeAll { $0.name == entry.name }
            Self.rekey(&model.entries, from: from, to: to)
            Self.rekey(&model.children, from: from, to: to)
            Self.rekey(&model.origins, from: from, to: to)
            Self.rekey(&model.links, from: from, to: to)
            model.entries[to] = moved
            model.children[PosixPath.parent(to), default: []].append(moved)
            changeCount += 1
        }
    }

    public func makeSymlink(_ path: String, target: String) throws {
        try modify(path) {
            try checkTarget(path, replaceable: false)
            let file = try nextStagedFile()
            guard symlink(target, file) == 0 else { throw FileError(path: path, errno: errno) }
            insert(FileEntry(name: PosixPath.name(path), isDirectory: false, isSymlink: true, modified: Date(), permissions: 0o755), at: path, origin: .staged(file))
            model.links[path] = target
        }
    }

    public func setModified(_ path: String, _ date: Date) throws {
        try modify(path) {
            guard let entry = model.entries[path] else { throw path == "/" ? FileError(path: path, errno: EPERM) : FileError(path: path, errno: ENOENT) }
            replace(entry.copy(modified: date), at: path)
            if case .staged(let file) = model.origins[path] { try LocalFileSystem.shared.setModified(file, date) }
        }
    }

    public func setPermissions(_ path: String, _ mode: UInt16) throws {
        try modify(path) {
            guard let entry = model.entries[path] else { throw path == "/" ? FileError(path: path, errno: EPERM) : FileError(path: path, errno: ENOENT) }
            replace(entry.copy(permissions: mode), at: path)
            if case .staged(let file) = model.origins[path], !entry.isSymlink { try LocalFileSystem.shared.setPermissions(file, mode) }
        }
    }

    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter {
        try locked {
            guard writable else { throw readOnly(path) }
            try checkTarget(path, replaceable: true)
            let automatic = depth == 0
            if automatic { start(); depth = 1 }
            do {
                let file = try nextStagedFile()
                let inner = try LocalFileSystem.shared.openWriter(file, permissions: permissions)
                return StagedWriter(
                    inner: inner,
                    finish: { [self] in try finishFile(file, at: path, permissions: permissions, automatic: automatic) },
                    abort: { [self] in abortFile(file, automatic: automatic) }
                )
            } catch {
                if automatic { discard() }
                throw error
            }
        }
    }

    private func readOnly(_ path: String) -> FileError {
        FileError(localized("%@ ist ein Archiv und nur lesbar", PosixPath.name(archivePath) as NSString))
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func modify(_ path: String, _ body: () throws -> Void) throws {
        let automatic: Bool = try locked {
            guard writable else { throw readOnly(path) }
            let automatic = depth == 0
            if automatic { start(); depth = 1 }
            do {
                try body()
            } catch {
                if automatic { discard() }
                throw error
            }
            return automatic
        }
        if automatic { try commit() }
    }

    private func start() {
        snapshot = model
        changeCount = 0
        stagedCount = 0
        stage = NSTemporaryDirectory() + "mc-archive-stage-" + UUID().uuidString
    }

    private func discard() {
        if let snapshot { model = snapshot }
        snapshot = nil
        depth = 0
        try? FileManager.default.removeItem(atPath: stage)
    }

    /// Schreibt die Änderungen. Die Sperre wird nur für das Vorbereiten und das
    /// Übernehmen gehalten, nicht während bsdtar das Archiv neu schreibt.
    private func commit() throws {
        let job: (changes: ArchiveChanges, saved: Model?)? = locked {
            guard depth > 0 else { return nil }
            depth -= 1
            guard depth == 0 else { return nil }
            let saved = snapshot
            guard changeCount > 0 else {
                cleanUp()
                return nil
            }
            return (pendingChanges(from: saved?.origins ?? [:]), saved)
        }
        guard let job else { return }
        var failure: Error?
        do { try ArchiveRewriter.apply(job.changes, to: archivePath) } catch { failure = error }
        try locked {
            defer { cleanUp() }
            do {
                if let failure { throw failure }
                try load()
            } catch {
                if let saved = job.saved { model = saved }
                throw error
            }
        }
    }

    private func cleanUp() {
        snapshot = nil
        try? FileManager.default.removeItem(atPath: stage)
    }

    private func stageFolder() throws -> String {
        try FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
        return stage
    }

    private func nextStagedFile() throws -> String {
        stagedCount += 1
        return try stageFolder() + "/n\(stagedCount)"
    }

    private func checkTarget(_ path: String, replaceable: Bool) throws {
        let parent = PosixPath.parent(path)
        guard path != "/", parent == "/" || model.entries[parent]?.isDirectory == true else { throw FileError(path: path, errno: ENOENT) }
        if let existing = model.entries[path], !(replaceable && !existing.isDirectory) { throw FileError(path: path, errno: EEXIST) }
    }

    private func finishFile(_ file: String, at path: String, permissions: UInt16, automatic: Bool) throws {
        locked {
            let size = (try? FileManager.default.attributesOfItem(atPath: file)[.size] as? Int64) ?? 0
            if model.entries[path] != nil { removeNode(path) }
            insert(FileEntry(name: PosixPath.name(path), isDirectory: false, size: size, modified: Date(), permissions: permissions & 0o777), at: path, origin: .staged(file))
        }
        if automatic { try commit() }
    }

    private func abortFile(_ file: String, automatic: Bool) {
        locked {
            try? FileManager.default.removeItem(atPath: file)
            if automatic { discard() }
        }
    }

    private func insert(_ entry: FileEntry, at path: String, origin: Origin) {
        register(entry, at: path)
        model.origins[path] = origin
        model.links[path] = nil
        if entry.isDirectory { model.children[path] = [] }
        changeCount += 1
    }

    private func removeNode(_ path: String) {
        let name = PosixPath.name(path)
        model.children[PosixPath.parent(path)]?.removeAll { $0.name == name }
        if case .staged(let file) = model.origins[path] { try? FileManager.default.removeItem(atPath: file) }
        model.entries[path] = nil
        model.origins[path] = nil
        model.links[path] = nil
        model.children[path] = nil
        changeCount += 1
    }

    private func replace(_ entry: FileEntry, at path: String) {
        if let index = model.children[PosixPath.parent(path)]?.firstIndex(where: { $0.name == entry.name }) {
            model.children[PosixPath.parent(path)]?[index] = entry
        }
        model.entries[path] = entry
    }

    private static func rekey<Value>(_ dictionary: inout [String: Value], from: String, to: String) {
        let prefix = from + "/"
        for key in Array(dictionary.keys) where key == from || key.hasPrefix(prefix) {
            dictionary[to + key.dropFirst(from.count)] = dictionary.removeValue(forKey: key)
        }
    }

    private func pendingChanges(from original: [String: Origin]) -> ArchiveChanges {
        var changes = ArchiveChanges()
        var survivors: [String: String] = [:]
        for (path, origin) in model.origins {
            if let source = origin.original {
                survivors[source] = path
            } else if case .staged(let file) = origin {
                changes.additions.append((file, path))
            }
        }
        changes.additions.sort { $0.archive < $1.archive }
        var ancestorsOfMoved = Set<String>()
        for (source, path) in survivors where source != path {
            var parent = PosixPath.parent(source)
            while parent != "/", ancestorsOfMoved.insert(parent).inserted { parent = PosixPath.parent(parent) }
        }
        let deleted = Set(original.values.compactMap(\.original)).subtracting(survivors.keys)
        let whole = deleted.subtracting(ancestorsOfMoved)
        for path in deleted.sorted() {
            if ancestorsOfMoved.contains(path) {
                changes.exactDeletions.append(path)
            } else if !Self.hasAncestor(of: path, in: whole) {
                changes.deletions.append(path)
            }
        }
        var rules: [String: String] = [:]
        for (source, path) in survivors.sorted(by: { Self.shallower($0.key, $1.key) }) {
            var expected = source
            var ancestor = PosixPath.parent(source)
            while ancestor != "/" {
                if let target = rules[ancestor] {
                    expected = target + source.dropFirst(ancestor.count)
                    break
                }
                ancestor = PosixPath.parent(ancestor)
            }
            if expected != path { rules[source] = path }
        }
        changes.renames = rules.sorted { Self.shallower($1.key, $0.key) }.map { ($0.key, $0.value) }
        return changes
    }

    private static func hasAncestor(of path: String, in paths: Set<String>) -> Bool {
        var parent = PosixPath.parent(path)
        while parent != "/" {
            if paths.contains(parent) { return true }
            parent = PosixPath.parent(parent)
        }
        return false
    }

    private static func shallower(_ first: String, _ second: String) -> Bool {
        let counts = (first.split(separator: "/").count, second.split(separator: "/").count)
        return counts.0 == counts.1 ? first < second : counts.0 < counts.1
    }

    private static func run(_ arguments: [String]) throws -> String {
        let tar = try Bsdtar(arguments, capturesOutput: true)
        let data = tar.output?.readDataToEndOfFile() ?? Data()
        if let detail = tar.failure() { throw unreadable(arguments.last ?? "", detail) }
        return String(decoding: data, as: UTF8.self)
    }

    fileprivate static func unreadable(_ archive: String, _ detail: String) -> FileError {
        let suffix = detail.isEmpty ? "" : ": " + detail
        return FileError(localized("Archiv lässt sich nicht lesen: %@", (PosixPath.name(archive) + suffix) as NSString))
    }

    private func load() throws {
        if writable, !FileManager.default.fileExists(atPath: archivePath) {
            model = Model()
            return
        }
        let listing = try Self.run(["-tvf", archivePath])
        model = Model()
        for line in listing.split(separator: "\n") { parse(String(line)) }
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
        model.origins[full] = .archive(path: full, member: member)
        if let target { model.links[full] = target }
        if isDirectory, model.children[full] == nil { model.children[full] = [] }
    }

    private func ensureParents(of path: String) {
        let parent = PosixPath.parent(path)
        guard parent != "/", model.entries[parent] == nil else { return }
        ensureParents(of: parent)
        register(FileEntry(name: PosixPath.name(parent), isDirectory: true), at: parent)
        model.origins[parent] = .implied(path: parent)
        model.children[parent] = model.children[parent] ?? []
    }

    private func register(_ entry: FileEntry, at path: String) {
        let parent = PosixPath.parent(path)
        if let existing = model.children[parent]?.firstIndex(where: { $0.name == entry.name }) {
            model.children[parent]?[existing] = entry
        } else {
            model.children[parent, default: []].append(entry)
        }
        model.entries[path] = entry
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

private enum Origin {
    case archive(path: String, member: String)
    case implied(path: String)
    case staged(String)

    var original: String? {
        switch self {
        case .archive(let path, _), .implied(let path): path
        case .staged: nil
        }
    }
}

private struct Model {
    var children: [String: [FileEntry]] = ["/": []]
    var entries: [String: FileEntry] = [:]
    var origins: [String: Origin] = [:]
    var links: [String: String] = [:]
}

private extension FileEntry {
    func copy(name: String? = nil, modified: Date? = nil, permissions: UInt16? = nil) -> FileEntry {
        FileEntry(name: name ?? self.name, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified ?? self.modified, permissions: permissions ?? self.permissions, accessed: accessed, changed: changed, created: created)
    }
}

private final class StagedWriter: FileWriter {
    private let inner: FileWriter
    private let onFinish: () throws -> Void
    private let onAbort: () -> Void

    init(inner: FileWriter, finish: @escaping () throws -> Void, abort: @escaping () -> Void) {
        self.inner = inner
        onFinish = finish
        onAbort = abort
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws { try inner.write(buffer) }

    func finish() throws {
        do {
            try inner.finish()
        } catch {
            onAbort()
            throw error
        }
        try onFinish()
    }

    func abort() {
        inner.abort()
        onAbort()
    }
}

private final class ArchiveReader: FileReader {
    private let archive: String
    private let tar: Bsdtar
    private let handle: FileHandle
    private var finished = false

    init(archive: String, member: String) throws {
        self.archive = archive
        let escaped = member.map { "*?[]\\".contains($0) ? "\\\($0)" : String($0) }.joined()
        tar = try Bsdtar(["-xOf", archive, escaped], capturesOutput: true)
        guard let output = tar.output else { throw ArchiveFileSystem.unreadable(archive, "") }
        handle = output
    }

    deinit { close() }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        while true {
            let count = Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            if count > 0 { return count }
            if count == 0 {
                guard !finished else { return 0 }
                finished = true
                try? handle.close()
                if let detail = tar.failure() { throw ArchiveFileSystem.unreadable(archive, detail) }
                return 0
            }
            if errno != EINTR { throw FileError(path: archive, errno: errno) }
        }
    }

    func close() {
        guard !finished else { return }
        finished = true
        tar.terminate()
        try? handle.close()
    }
}
