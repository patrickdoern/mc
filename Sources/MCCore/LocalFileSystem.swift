import Foundation

public final class LocalFileSystem: FileSystem {
    public static let shared = LocalFileSystem()

    public let identity = "local"
    public var homePath: String { NSHomeDirectory() }

    public func list(_ path: String) throws -> [FileEntry] {
        guard let directory = opendir(path) else { throw FileError(path: path, errno: errno) }
        defer { closedir(directory) }
        let descriptor = dirfd(directory)
        var entries: [FileEntry] = []
        while let item = readdir(directory) {
            let name = withUnsafePointer(to: &item.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(item.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            if let entry = Self.entry(named: name, at: descriptor) { entries.append(entry) }
        }
        return entries
    }

    public func stat(_ path: String) throws -> FileEntry {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { throw FileError(path: path, errno: errno) }
        return Self.entry(named: PosixPath.name(path), info: info, followingLinkAt: path)
    }

    public func statFollowingLinks(_ path: String) throws -> FileEntry {
        var info = Darwin.stat()
        guard fstatat(AT_FDCWD, path, &info, 0) == 0 else { throw FileError(path: path, errno: errno) }
        return Self.entry(named: PosixPath.name(path), info: info, isSymlink: false, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR)
    }

    public func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func makeDirectory(_ path: String) throws {
        guard mkdir(path, 0o755) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func removeFile(_ path: String) throws {
        guard unlink(path) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func removeDirectory(_ path: String) throws {
        guard rmdir(path) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func rename(_ from: String, _ to: String) throws {
        guard Darwin.rename(from, to) == 0 else { throw FileError(path: from, errno: errno) }
    }

    public func readLink(_ path: String) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink(path, &buffer, Int(PATH_MAX))
        guard length >= 0 else { throw FileError(path: path, errno: errno) }
        return String(cString: Array(buffer[0..<length]) + [0])
    }

    public func makeSymlink(_ path: String, target: String) throws {
        guard symlink(target, path) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func setModified(_ path: String, _ date: Date) throws {
        let seconds = date.timeIntervalSince1970
        let stamp = timespec(tv_sec: Int(seconds), tv_nsec: Int((seconds - floor(seconds)) * 1_000_000_000))
        let times = [stamp, stamp]
        guard utimensat(AT_FDCWD, path, times, AT_SYMLINK_NOFOLLOW) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func setPermissions(_ path: String, _ mode: UInt16) throws {
        guard chmod(path, mode_t(mode & 0o7777)) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func makeHardLink(_ path: String, to existing: String) throws {
        guard link(existing, path) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func setOwner(_ path: String, user: String?, group: String?) throws {
        var owner = uid_t.max
        var groupID = gid_t.max
        if let user, !user.isEmpty {
            guard let entry = getpwnam(user) else { throw FileError(localized("Unbekannter Benutzer: %@", user as NSString)) }
            owner = entry.pointee.pw_uid
        }
        if let group, !group.isEmpty {
            guard let entry = getgrnam(group) else { throw FileError(localized("Unbekannte Gruppe: %@", group as NSString)) }
            groupID = entry.pointee.gr_gid
        }
        guard chown(path, owner, groupID) == 0 else { throw FileError(path: path, errno: errno) }
    }

    public func openReader(_ path: String) throws -> FileReader {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { throw FileError(path: path, errno: errno) }
        return LocalFile(descriptor: descriptor, path: path)
    }

    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter {
        try openWriter(path, permissions: permissions, followingLinks: true)
    }

    func openWriter(_ path: String, permissions: UInt16, followingLinks: Bool) throws -> FileWriter {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | (followingLinks ? 0 : O_NOFOLLOW), mode_t(permissions & 0o777))
        guard descriptor >= 0 else { throw FileError(path: path, errno: errno) }
        return LocalFile(descriptor: descriptor, path: path)
    }

    public func adoptMetadata(of original: String, to path: String) {
        copyfile(original, path, nil, copyfile_flags_t(COPYFILE_METADATA))
    }

    public func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    private static func entry(named name: String, at directory: Int32) -> FileEntry? {
        var info = Darwin.stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        guard (info.st_mode & S_IFMT) == S_IFLNK else { return entry(named: name, info: info, isSymlink: false, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR) }
        var target = Darwin.stat()
        let isDirectory = fstatat(directory, name, &target, 0) == 0 && (target.st_mode & S_IFMT) == S_IFDIR
        return entry(named: name, info: info, isSymlink: true, isDirectory: isDirectory)
    }

    private static func entry(named name: String, info: Darwin.stat, followingLinkAt path: String) -> FileEntry {
        guard (info.st_mode & S_IFMT) == S_IFLNK else { return entry(named: name, info: info, isSymlink: false, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR) }
        var target = Darwin.stat()
        let isDirectory = fstatat(AT_FDCWD, path, &target, 0) == 0 && (target.st_mode & S_IFMT) == S_IFDIR
        return entry(named: name, info: info, isSymlink: true, isDirectory: isDirectory)
    }

    private static func entry(named name: String, info: Darwin.stat, isSymlink: Bool, isDirectory: Bool) -> FileEntry {
        FileEntry(
            name: name,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: Int64(info.st_size),
            modified: date(info.st_mtimespec),
            permissions: UInt16(info.st_mode & 0o7777),
            accessed: date(info.st_atimespec),
            changed: date(info.st_ctimespec),
            created: date(info.st_birthtimespec)
        )
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}

private final class LocalFile: FileReader, FileWriter {
    private var descriptor: Int32
    private let path: String

    init(descriptor: Int32, path: String) {
        self.descriptor = descriptor
        self.path = path
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        while true {
            let count = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            if count >= 0 { return count }
            if errno != EINTR { throw FileError(path: path, errno: errno) }
        }
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
            if count >= 0 {
                offset += count
            } else if errno != EINTR {
                throw FileError(path: path, errno: errno)
            }
        }
    }

    func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    func abort() { close() }

    func finish() throws {
        guard descriptor >= 0 else { return }
        let result = Darwin.close(descriptor)
        descriptor = -1
        if result != 0 { throw FileError(path: path, errno: errno) }
    }
}
