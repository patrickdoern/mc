import Foundation

public final class LinkShare {
    private struct Folder {
        let name: String
        let path: String
    }

    private struct Location {
        let virtual: String
        let folder: Folder
        let local: String
        let isFolder: Bool
    }

    private struct OpenFile {
        let reader: FileReader
        let virtual: String
        let local: String
    }

    private struct WrittenFile {
        let writer: FileWriter
        let virtual: String
        let local: String
    }

    private let fileSystem = LocalFileSystem.shared
    private let folders: [Folder]
    private let writable: Bool
    private var openFiles: [UInt32: OpenFile] = [:]
    private var writtenFiles: [UInt32: WrittenFile] = [:]
    private var nextHandle: UInt32 = 1

    public init(folders paths: [String], writable: Bool) {
        var folders: [Folder] = []
        for path in paths {
            let resolved = LocalFileSystem.shared.canonicalPath(path) ?? PosixPath.normalize(path)
            let base = PosixPath.name(resolved)
            var name = base
            var counter = 2
            while folders.contains(where: { $0.name == name }) {
                name = "\(base) (\(counter))"
                counter += 1
            }
            folders.append(Folder(name: name, path: resolved))
        }
        self.folders = folders
        self.writable = writable
    }

    public func answer(_ frame: LinkFrame) -> [LinkFrame] {
        let messages: [LinkMessage]
        do {
            messages = try result(for: frame.message)
        } catch {
            messages = [.error(error.localizedDescription)]
        }
        return messages.map { LinkFrame(requestID: frame.requestID, message: $0) }
    }

    public func end() {
        writtenFiles.values.forEach { $0.writer.abort() }
        writtenFiles = [:]
        openFiles.values.forEach { $0.reader.close() }
        openFiles = [:]
    }

    private func result(for message: LinkMessage) throws -> [LinkMessage] {
        switch message {
        case .list(let path): return LinkMessage.entryBatches(try list(path))
        case .stat(let path): return [.entry(try stat(path))]
        case .statFollowingLinks(let path): return [.entry(try statFollowingLinks(path))]
        case .readLink(let path): return [.text(try readLink(path))]
        case .openRead(let path): return [.handle(try openRead(path))]
        case .read(let handle, let length): return [.data(try read(handle, length: Int(length)))]
        case .close(let handle):
            openFiles.removeValue(forKey: handle)?.reader.close()
            return [.done]
        default:
            guard writable else { throw FileError(localized("Die Freigabe ist nur lesbar")) }
            return try change(message)
        }
    }

    private func change(_ message: LinkMessage) throws -> [LinkMessage] {
        switch message {
        case .makeDirectory(let path): try changeEntry(path) { try fileSystem.makeDirectory($0) }
        case .removeFile(let path): try changeEntry(path) { try fileSystem.removeFile($0) }
        case .removeDirectory(let path): try changeEntry(path) { try fileSystem.removeDirectory($0) }
        case .trash(let path): try changeEntry(path) { try fileSystem.trash($0) }
        case .rename(let from, let to): try rename(from, to)
        case .makeSymlink(let path, let target): try makeSymlink(path, target: target)
        case .setModified(let path, let date): try changeTarget(path) { try fileSystem.setModified($0, date) }
        case .setPermissions(let path, let mode): try changeTarget(path) { try fileSystem.setPermissions($0, mode & 0o777) }
        case .openWrite(let path, let permissions): return [.handle(try openWrite(path, permissions: permissions))]
        case .write(let handle, let data): try write(handle, data)
        case .finish(let handle):
            guard let file = writtenFiles.removeValue(forKey: handle) else { throw FileError(String(cString: strerror(EBADF))) }
            try mapping(file.virtual, file.local) { try file.writer.finish() }
        case .abort(let handle): writtenFiles.removeValue(forKey: handle)?.writer.abort()
        default: throw FileError(String(cString: strerror(ENOTSUP)))
        }
        return [.done]
    }

    private func list(_ path: String) throws -> [FileEntry] {
        guard let location = try location(path) else {
            return folders.compactMap { folder in (try? fileSystem.stat(folder.path)).map { renamed($0, folder.name) } }
        }
        let real = try followed(location)
        return try mapping(location.virtual, real) { try fileSystem.list(real) }
    }

    private func stat(_ path: String) throws -> FileEntry {
        guard let location = try location(path) else { return Self.rootEntry }
        let local = try unfollowed(location)
        return renamed(try mapping(location.virtual, local) { try fileSystem.stat(local) }, PosixPath.name(location.virtual))
    }

    private func statFollowingLinks(_ path: String) throws -> FileEntry {
        guard let location = try location(path) else { return Self.rootEntry }
        let real = try followed(location)
        return renamed(try mapping(location.virtual, real) { try fileSystem.statFollowingLinks(real) }, PosixPath.name(location.virtual))
    }

    private func readLink(_ path: String) throws -> String {
        guard let location = try location(path) else { throw FileError(path: path, errno: EINVAL) }
        let local = try unfollowed(location)
        let target = try mapping(location.virtual, local) { try fileSystem.readLink(local) }
        if target.hasPrefix("/") {
            guard let real = fileSystem.canonicalPath(local), let virtual = virtualPath(real) else { throw outside() }
            return virtual
        }
        guard Self.isInside(PosixPath.normalize(PosixPath.join(PosixPath.parent(local), target)), location.folder.path) else { throw outside() }
        return target
    }

    private func openRead(_ path: String) throws -> UInt32 {
        guard let location = try location(path) else { throw FileError(path: path, errno: EISDIR) }
        let real = try followed(location)
        let reader = try mapping(location.virtual, real) { try fileSystem.openReader(real) }
        let handle = nextHandle
        nextHandle += 1
        openFiles[handle] = OpenFile(reader: reader, virtual: location.virtual, local: real)
        return handle
    }

    private func read(_ handle: UInt32, length: Int) throws -> Data {
        guard let file = openFiles[handle] else { throw FileError(String(cString: strerror(EBADF))) }
        var buffer = [UInt8](repeating: 0, count: min(length, LinkProtocol.maximumBlock))
        let count = try mapping(file.virtual, file.local) { try buffer.withUnsafeMutableBytes { try file.reader.read(into: $0) } }
        return Data(buffer[0..<count])
    }

    private func rename(_ from: String, _ to: String) throws {
        let source = try changeable(from)
        let target = try changeable(to)
        guard source.folder.name == target.folder.name else { throw outside() }
        let sourceLocal = try unfollowed(source)
        let targetLocal = try unfollowed(target)
        try mapping(target.virtual, targetLocal) { try mapping(source.virtual, sourceLocal) { try fileSystem.rename(sourceLocal, targetLocal) } }
    }

    private func makeSymlink(_ path: String, target: String) throws {
        let location = try changeable(path)
        let local = try unfollowed(location)
        guard !target.hasPrefix("/"), Self.isInside(PosixPath.normalize(PosixPath.join(PosixPath.parent(local), target)), location.folder.path) else { throw outside() }
        try mapping(location.virtual, local) { try fileSystem.makeSymlink(local, target: target) }
    }

    private func openWrite(_ path: String, permissions: UInt16) throws -> UInt32 {
        let location = try changeable(path)
        let entry = try unfollowed(location)
        let local = (try? fileSystem.stat(entry)) == nil ? entry : try followed(location)
        let writer = try mapping(location.virtual, local) { try fileSystem.openWriter(local, permissions: permissions, followingLinks: false) }
        let handle = nextHandle
        nextHandle += 1
        writtenFiles[handle] = WrittenFile(writer: writer, virtual: location.virtual, local: local)
        return handle
    }

    private func write(_ handle: UInt32, _ data: Data) throws {
        guard let file = writtenFiles[handle] else { throw FileError(String(cString: strerror(EBADF))) }
        try mapping(file.virtual, file.local) { try data.withUnsafeBytes { try file.writer.write($0) } }
    }

    private func changeEntry(_ path: String, _ body: (String) throws -> Void) throws {
        let location = try changeable(path)
        let local = try unfollowed(location)
        try mapping(location.virtual, local) { try body(local) }
    }

    private func changeTarget(_ path: String, _ body: (String) throws -> Void) throws {
        let location = try changeable(path)
        let real = try followed(location)
        guard real != location.folder.path else { throw unchangeable() }
        try mapping(location.virtual, real) { try body(real) }
    }

    private func changeable(_ path: String) throws -> Location {
        let name = path.split(separator: "/").last
        guard name != "." && name != ".." else { throw FileError(path: path, errno: EINVAL) }
        let parts = try parts(path)
        guard parts.count > 1, let location = try location(parts) else { throw unchangeable() }
        return location
    }

    private func location(_ path: String) throws -> Location? {
        try location(parts(path))
    }

    private func parts(_ path: String) throws -> [Substring] {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard parts.popLast() != nil else { throw outside() }
            } else {
                parts.append(part)
            }
        }
        return parts
    }

    private func location(_ parts: [Substring]) throws -> Location? {
        guard let first = parts.first else { return nil }
        let virtual = "/" + parts.joined(separator: "/")
        guard let folder = folders.first(where: { $0.name == first }) else { throw FileError(path: virtual, errno: ENOENT) }
        let local = parts.dropFirst().reduce(folder.path) { PosixPath.join($0, String($1)) }
        return Location(virtual: virtual, folder: folder, local: local, isFolder: parts.count == 1)
    }

    private func followed(_ location: Location) throws -> String {
        guard let real = fileSystem.canonicalPath(location.local) else { throw FileError(path: location.virtual, errno: errno) }
        guard Self.isInside(real, location.folder.path) else { throw outside() }
        return real
    }

    private func unfollowed(_ location: Location) throws -> String {
        guard !location.isFolder else { return location.folder.path }
        let parent = Location(virtual: PosixPath.parent(location.virtual), folder: location.folder, local: PosixPath.parent(location.local), isFolder: false)
        return PosixPath.join(try followed(parent), PosixPath.name(location.local))
    }

    private func virtualPath(_ real: String) -> String? {
        guard let folder = folders.first(where: { Self.isInside(real, $0.path) }) else { return nil }
        return "/" + folder.name + real.dropFirst(folder.path.count)
    }

    private func mapping<T>(_ virtual: String, _ local: String, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw FileError(error.localizedDescription.replacingOccurrences(of: local, with: virtual))
        }
    }

    private func renamed(_ entry: FileEntry, _ name: String) -> FileEntry {
        FileEntry(name: name, isDirectory: entry.isDirectory, isSymlink: entry.isSymlink, size: entry.size, modified: entry.modified, permissions: entry.permissions, accessed: entry.accessed, changed: entry.changed, created: entry.created)
    }

    private func outside() -> FileError {
        FileError(localized("Außerhalb der Freigabe"))
    }

    private func unchangeable() -> FileError {
        FileError(localized("Freigegebene Ordner lassen sich nicht ändern"))
    }

    private static let rootEntry = FileEntry(name: "", isDirectory: true, permissions: 0o555)

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
