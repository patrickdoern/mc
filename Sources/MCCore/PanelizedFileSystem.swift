import Foundation

public final class PanelizedFileSystem: FileSystem {
    public let identity = "panelized://" + UUID().uuidString
    public let displayName: String
    public var homePath: String { "/" }
    public var exitLocation: ExitLocation? { ExitLocation(system: base, path: root, selecting: nil) }

    private let base: FileSystem
    private let root: String
    private let relativePaths: [String]

    public init(base: FileSystem, paths: [String], title: String) {
        self.base = base
        displayName = title
        root = Self.commonAncestor(of: paths)
        relativePaths = paths.map { Self.relative($0, to: Self.commonAncestor(of: paths)) }
    }

    public func list(_ path: String) throws -> [FileEntry] {
        guard path == "/" else { return try base.list(mapped(path)) }
        return relativePaths.compactMap { relative in
            guard let entry = try? base.stat(PosixPath.join(root, relative)) else { return nil }
            return FileEntry(name: relative, isDirectory: entry.isDirectory, isSymlink: entry.isSymlink, size: entry.size, modified: entry.modified, permissions: entry.permissions)
        }
    }

    public func stat(_ path: String) throws -> FileEntry { try base.stat(mapped(path)) }
    public func removeFile(_ path: String) throws { try base.removeFile(mapped(path)) }
    public func removeDirectory(_ path: String) throws { try base.removeDirectory(mapped(path)) }
    public func readLink(_ path: String) throws -> String { try base.readLink(mapped(path)) }
    public func setModified(_ path: String, _ date: Date) throws { try base.setModified(mapped(path), date) }
    public func setPermissions(_ path: String, _ mode: UInt16) throws { try base.setPermissions(mapped(path), mode) }
    public func openReader(_ path: String) throws -> FileReader { try base.openReader(mapped(path)) }

    public func makeDirectory(_ path: String) throws { throw unsupported() }
    public func rename(_ from: String, _ to: String) throws { throw unsupported() }
    public func makeSymlink(_ path: String, target: String) throws { throw unsupported() }
    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter { throw unsupported() }

    private func unsupported() -> FileError {
        FileError(localized("In einer Ergebnisliste ist diese Aktion nicht möglich"))
    }

    private func mapped(_ path: String) -> String {
        PosixPath.join(root, String(path.drop { $0 == "/" }))
    }

    private static func commonAncestor(of paths: [String]) -> String {
        guard var common = paths.first.map({ PosixPath.parent($0).split(separator: "/").map(String.init) }) else { return "/" }
        for path in paths.dropFirst() {
            let parts = PosixPath.parent(path).split(separator: "/").map(String.init)
            common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
        }
        return "/" + common.joined(separator: "/")
    }

    private static func relative(_ path: String, to root: String) -> String {
        root == "/" ? String(path.drop { $0 == "/" }) : String(path.dropFirst(root.count + 1))
    }
}
