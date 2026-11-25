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

    private let fileSystem = LocalFileSystem.shared
    private let folders: [Folder]
    private var openFiles: [UInt32: OpenFile] = [:]
    private var nextHandle: UInt32 = 1

    public init(folders paths: [String]) {
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
        default: throw FileError(localized("Die Freigabe ist nur lesbar"))
        }
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

    private func location(_ path: String) throws -> Location? {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard parts.popLast() != nil else { throw outside() }
            } else {
                parts.append(part)
            }
        }
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

    private static let rootEntry = FileEntry(name: "", isDirectory: true, permissions: 0o555)

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
