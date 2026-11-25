import Foundation

public struct FileError: LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public init(path: String, errno code: Int32) {
        self.message = "\(path): \(String(cString: strerror(code)))"
    }

    public var errorDescription: String? { message }
}

public protocol FileReader: AnyObject {
    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int
    func close()
}

public protocol FileWriter: AnyObject {
    func write(_ buffer: UnsafeRawBufferPointer) throws
    func finish() throws
    func abort()
}

public struct ExitLocation {
    public let system: FileSystem
    public let path: String
    public let selecting: String?

    public init(system: FileSystem, path: String, selecting: String?) {
        self.system = system
        self.path = path
        self.selecting = selecting
    }
}

public protocol FileSystem: AnyObject {
    var identity: String { get }
    var displayName: String { get }
    var exitLocation: ExitLocation? { get }
    var homePath: String { get }
    var hasPendingChanges: Bool { get }
    var isDisconnected: Bool { get }
    func beginTransaction()
    func commitTransaction() throws
    func rollbackTransaction()
    func list(_ path: String) throws -> [FileEntry]
    func stat(_ path: String) throws -> FileEntry
    func statFollowingLinks(_ path: String) throws -> FileEntry
    func canonicalPath(_ path: String) -> String?
    func makeDirectory(_ path: String) throws
    func removeFile(_ path: String) throws
    func removeDirectory(_ path: String) throws
    func rename(_ from: String, _ to: String) throws
    func readLink(_ path: String) throws -> String
    func makeSymlink(_ path: String, target: String) throws
    func setModified(_ path: String, _ date: Date) throws
    func setPermissions(_ path: String, _ mode: UInt16) throws
    func openReader(_ path: String) throws -> FileReader
    func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter
    func adoptMetadata(of original: String, to path: String)
}

public protocol TrashingFileSystem: FileSystem {
    func trash(_ path: String) throws
}

public extension FileSystem {
    var displayName: String { identity.replacingOccurrences(of: "sftp://", with: "") }

    var exitLocation: ExitLocation? { nil }

    var hasPendingChanges: Bool { false }

    var isDisconnected: Bool { false }

    func beginTransaction() {}

    func commitTransaction() throws {}

    func rollbackTransaction() {}

    func statFollowingLinks(_ path: String) throws -> FileEntry { try stat(path) }

    func canonicalPath(_ path: String) -> String? { nil }

    func adoptMetadata(of original: String, to path: String) {}

    func replace(_ path: String, with temporary: String) throws {
        if (try? rename(temporary, path)) != nil { return }
        do {
            try removeFile(path)
        } catch {
            try? removeFile(temporary)
            throw error
        }
        do {
            try rename(temporary, path)
        } catch {
            throw FileError(localized("%@ konnte nicht ersetzt werden, der neue Inhalt liegt in %@", path as NSString, temporary as NSString))
        }
    }

    func writeAllSafely(_ data: Data, to path: String, permissions: UInt16) throws {
        guard let existing = try? stat(path) else { return try writeAll(data, to: path, permissions: permissions) }
        guard let target = existing.isSymlink ? canonicalPath(path) : path else { return try writeAll(data, to: path, permissions: permissions) }
        let temporary = PosixPath.join(PosixPath.parent(target), "." + PosixPath.name(target) + ".mc-save-" + UUID().uuidString)
        do {
            try writeAll(data, to: temporary, permissions: permissions)
        } catch {
            try? removeFile(temporary)
            return try writeAll(data, to: target, permissions: permissions)
        }
        adoptMetadata(of: target, to: temporary)
        try replace(target, with: temporary)
    }

    func exists(_ path: String) -> Bool { (try? stat(path)) != nil }

    func makeDirectories(_ path: String) throws {
        if let existing = try? stat(path) {
            guard existing.isDirectory else { throw FileError(localized("%@: Existiert bereits und ist kein Ordner", path as NSString)) }
            return
        }
        if path != "/" { try makeDirectories(PosixPath.parent(path)) }
        try makeDirectory(path)
    }

    func readAll(_ path: String) throws -> Data {
        let reader = try openReader(path)
        defer { reader.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        while true {
            let count = try buffer.withUnsafeMutableBytes { try reader.read(into: $0) }
            if count == 0 { return data }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    func writeAll(_ data: Data, to path: String, permissions: UInt16) throws {
        let writer = try openWriter(path, permissions: permissions)
        do {
            try data.withUnsafeBytes { try writer.write($0) }
        } catch {
            writer.abort()
            throw error
        }
        try writer.finish()
    }
}
