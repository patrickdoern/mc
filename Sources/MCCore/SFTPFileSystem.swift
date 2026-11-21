import CLibSSH2
import Foundation

public final class SFTPFileSystem: FileSystem {
    public let identity: String
    public private(set) var homePath = "/"
    public let settings: SSHSettings
    let session: SSHSession
    let sftp: OpaquePointer
    let lock = NSRecursiveLock()

    private static let directoryType: UInt = 0o040000
    private static let linkType: UInt = 0o120000
    private static let typeMask: UInt = 0o170000

    public init(settings: SSHSettings, interaction: SSHInteraction) throws {
        self.settings = settings
        identity = "sftp://\(settings.user)@\(settings.hostName):\(settings.port)"
        session = try SSHSession(settings: settings, interaction: interaction)
        guard let sftp = libssh2_sftp_init(session.handle) else {
            let error = session.lastError("SFTP")
            session.disconnect()
            throw error
        }
        self.sftp = sftp
        homePath = (try? resolve(".")) ?? "/"
    }

    deinit {
        libssh2_sftp_shutdown(sftp)
        session.disconnect()
    }

    public func list(_ path: String) throws -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let directory = libssh2_sftp_open_ex(sftp, path, UInt32(path.utf8.count), 0, 0, LIBSSH2_SFTP_OPENDIR) else { throw failure(path) }
        defer { libssh2_sftp_close_handle(directory) }
        var entries: [FileEntry] = []
        var nameBuffer = [CChar](repeating: 0, count: 4096)
        while true {
            var attributes = LIBSSH2_SFTP_ATTRIBUTES()
            let length = libssh2_sftp_readdir_ex(directory, &nameBuffer, nameBuffer.count, nil, 0, &attributes)
            if length == 0 { break }
            guard length > 0 else { throw failure(path, code: Int32(length)) }
            let name = String(decoding: nameBuffer[0..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == "." || name == ".." { continue }
            entries.append(resolvingLink(Self.entry(named: name, attributes: attributes), at: PosixPath.join(path, name)))
        }
        return entries
    }

    public func stat(_ path: String) throws -> FileEntry {
        lock.lock()
        defer { lock.unlock() }
        var attributes = LIBSSH2_SFTP_ATTRIBUTES()
        let code = libssh2_sftp_stat_ex(sftp, path, UInt32(path.utf8.count), LIBSSH2_SFTP_LSTAT, &attributes)
        guard code == 0 else { throw failure(path, code: code) }
        return resolvingLink(Self.entry(named: PosixPath.name(path), attributes: attributes), at: path)
    }

    public func makeDirectory(_ path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let code = libssh2_sftp_mkdir_ex(sftp, path, UInt32(path.utf8.count), 0o755)
        guard code == 0 else { throw failure(path, code: code) }
    }

    public func removeFile(_ path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let code = libssh2_sftp_unlink_ex(sftp, path, UInt32(path.utf8.count))
        guard code == 0 else { throw failure(path, code: code) }
    }

    public func removeDirectory(_ path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let code = libssh2_sftp_rmdir_ex(sftp, path, UInt32(path.utf8.count))
        guard code == 0 else { throw failure(path, code: code) }
    }

    public func rename(_ from: String, _ to: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let code = libssh2_sftp_rename_ex(sftp, from, UInt32(from.utf8.count), to, UInt32(to.utf8.count), Int(LIBSSH2_SFTP_RENAME_OVERWRITE | LIBSSH2_SFTP_RENAME_ATOMIC | LIBSSH2_SFTP_RENAME_NATIVE))
        guard code == 0 else { throw failure(from, code: code) }
    }

    public func readLink(_ path: String) throws -> String {
        try pathRequest(path, type: LIBSSH2_SFTP_READLINK)
    }

    public func makeSymlink(_ path: String, target: String) throws {
        throw FileError(localized("%@: Symlinks können über SFTP nicht angelegt werden", path as NSString))
    }

    public func setModified(_ path: String, _ date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        var attributes = LIBSSH2_SFTP_ATTRIBUTES()
        attributes.flags = UInt(LIBSSH2_SFTP_ATTR_ACMODTIME)
        attributes.atime = UInt(date.timeIntervalSince1970)
        attributes.mtime = UInt(date.timeIntervalSince1970)
        let code = libssh2_sftp_stat_ex(sftp, path, UInt32(path.utf8.count), LIBSSH2_SFTP_SETSTAT, &attributes)
        guard code == 0 else { throw failure(path, code: code) }
    }

    public func setPermissions(_ path: String, _ mode: UInt16) throws {
        lock.lock()
        defer { lock.unlock() }
        var attributes = LIBSSH2_SFTP_ATTRIBUTES()
        attributes.flags = UInt(LIBSSH2_SFTP_ATTR_PERMISSIONS)
        attributes.permissions = UInt(mode & 0o7777)
        let code = libssh2_sftp_stat_ex(sftp, path, UInt32(path.utf8.count), LIBSSH2_SFTP_SETSTAT, &attributes)
        guard code == 0 else { throw failure(path, code: code) }
    }

    public func openReader(_ path: String) throws -> FileReader {
        try SFTPFile(owner: self, path: path, flags: UInt(LIBSSH2_FXF_READ), permissions: 0)
    }

    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter {
        try SFTPFile(owner: self, path: path, flags: UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC), permissions: Int(permissions & 0o777))
    }

    func failure(_ path: String, code: Int32? = nil) -> FileError {
        guard code == nil || code == LIBSSH2_ERROR_SFTP_PROTOCOL else { return session.lastError(path) }
        let status = libssh2_sftp_last_error(sftp)
        let reason: String
        switch status {
        case 2: reason = localized("Datei nicht gefunden")
        case 3: reason = localized("Zugriff verweigert")
        case 11: reason = localized("Existiert bereits")
        case 12: reason = localized("Schreibgeschützt")
        case 14: reason = localized("Kein Speicherplatz mehr")
        case 15: reason = localized("Kontingent überschritten")
        case 18: reason = localized("Ordner ist nicht leer")
        case 19: reason = localized("Ist ein Ordner")
        default: reason = localized("SFTP-Fehler %lu", status)
        }
        return FileError("\(path): \(reason)")
    }

    private func resolve(_ path: String) throws -> String {
        try pathRequest(path, type: LIBSSH2_SFTP_REALPATH)
    }

    private func pathRequest(_ path: String, type: Int32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var buffer = [CChar](repeating: 0, count: 4096)
        let code = libssh2_sftp_symlink_ex(sftp, path, UInt32(path.utf8.count), &buffer, UInt32(buffer.count - 1), type)
        guard code > 0 else { throw failure(path, code: code) }
        return String(decoding: buffer[0..<Int(code)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func resolvingLink(_ entry: FileEntry, at path: String) -> FileEntry {
        guard entry.isSymlink else { return entry }
        var attributes = LIBSSH2_SFTP_ATTRIBUTES()
        guard libssh2_sftp_stat_ex(sftp, path, UInt32(path.utf8.count), LIBSSH2_SFTP_STAT, &attributes) == 0 else { return entry }
        return FileEntry(name: entry.name, isDirectory: UInt(attributes.permissions) & Self.typeMask == Self.directoryType, isSymlink: true, size: entry.size, modified: entry.modified, permissions: entry.permissions, accessed: entry.accessed, changed: entry.changed, created: entry.created)
    }

    private static func entry(named name: String, attributes: LIBSSH2_SFTP_ATTRIBUTES) -> FileEntry {
        let hasPermissions = attributes.flags & UInt(LIBSSH2_SFTP_ATTR_PERMISSIONS) != 0
        let type = UInt(attributes.permissions) & typeMask
        return FileEntry(
            name: name,
            isDirectory: hasPermissions && type == directoryType,
            isSymlink: hasPermissions && type == linkType,
            size: attributes.flags & UInt(LIBSSH2_SFTP_ATTR_SIZE) != 0 ? Int64(attributes.filesize) : 0,
            modified: attributes.flags & UInt(LIBSSH2_SFTP_ATTR_ACMODTIME) != 0 ? Date(timeIntervalSince1970: TimeInterval(attributes.mtime)) : nil,
            permissions: hasPermissions ? UInt16(attributes.permissions & 0o7777) : 0o644,
            accessed: attributes.flags & UInt(LIBSSH2_SFTP_ATTR_ACMODTIME) != 0 ? Date(timeIntervalSince1970: TimeInterval(attributes.atime)) : nil
        )
    }
}

private final class SFTPFile: FileReader, FileWriter {
    private let owner: SFTPFileSystem
    private let path: String
    private var handle: OpaquePointer?

    init(owner: SFTPFileSystem, path: String, flags: UInt, permissions: Int) throws {
        self.owner = owner
        self.path = path
        owner.lock.lock()
        defer { owner.lock.unlock() }
        guard let handle = libssh2_sftp_open_ex(owner.sftp, path, UInt32(path.utf8.count), flags, permissions, LIBSSH2_SFTP_OPENFILE) else { throw owner.failure(path) }
        self.handle = handle
    }

    deinit { abort() }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        owner.lock.lock()
        defer { owner.lock.unlock() }
        let count = libssh2_sftp_read(handle, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count)
        guard count >= 0 else { throw owner.failure(path, code: Int32(count)) }
        return count
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < buffer.count {
            owner.lock.lock()
            let count = libssh2_sftp_write(handle, buffer.baseAddress.map { ($0 + offset).assumingMemoryBound(to: CChar.self) }, buffer.count - offset)
            let error = count < 0 ? owner.failure(path, code: Int32(count)) : nil
            owner.lock.unlock()
            if let error { throw error }
            offset += count
        }
    }

    func close() { abort() }

    func finish() throws {
        guard let handle else { return }
        owner.lock.lock()
        defer { owner.lock.unlock() }
        self.handle = nil
        let code = libssh2_sftp_close_handle(handle)
        guard code == 0 else { throw owner.failure(path, code: code) }
    }

    func abort() {
        guard let handle else { return }
        owner.lock.lock()
        libssh2_sftp_close_handle(handle)
        owner.lock.unlock()
        self.handle = nil
    }
}
