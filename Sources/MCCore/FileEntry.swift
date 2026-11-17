import Foundation

public struct FileEntry: Hashable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modified: Date?
    public let permissions: UInt16

    public init(name: String, isDirectory: Bool, isSymlink: Bool = false, size: Int64 = 0, modified: Date? = nil, permissions: UInt16 = 0o644) {
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }

    public var isHidden: Bool { name.hasPrefix(".") }

    public var fileExtension: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
}
