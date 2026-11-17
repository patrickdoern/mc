import Foundation

public struct SearchCriteria {
    public var namePattern: String
    public var content: String?

    public init(namePattern: String, content: String?) {
        self.namePattern = namePattern
        self.content = content
    }
}

public enum FileSearch {
    private static let maxContentSize: Int64 = 50_000_000

    public static func run(on fileSystem: FileSystem, root: String, criteria: SearchCriteria, isCancelled: () -> Bool, onMatch: (String) -> Void) {
        let needle = criteria.content.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
        visit(root, fileSystem, criteria.namePattern.isEmpty ? "*" : criteria.namePattern, needle, isCancelled, onMatch)
    }

    private static func visit(_ directory: String, _ fileSystem: FileSystem, _ pattern: String, _ needle: Data?, _ isCancelled: () -> Bool, _ onMatch: (String) -> Void) {
        guard !isCancelled(), let entries = try? fileSystem.list(directory) else { return }
        for entry in entries {
            if isCancelled() { return }
            let path = PosixPath.join(directory, entry.name)
            let matchesName = fnmatch(pattern, entry.name, FNM_CASEFOLD) == 0
            if entry.isDirectory {
                if matchesName && needle == nil { onMatch(path) }
                if !entry.isSymlink { visit(path, fileSystem, pattern, needle, isCancelled, onMatch) }
            } else if matchesName && (needle == nil || contains(needle!, in: path, entry, fileSystem)) {
                onMatch(path)
            }
        }
    }

    private static func contains(_ needle: Data, in path: String, _ entry: FileEntry, _ fileSystem: FileSystem) -> Bool {
        guard fileSystem is LocalFileSystem, !entry.isSymlink, entry.size <= maxContentSize, let data = try? fileSystem.readAll(path) else { return false }
        return data.range(of: needle) != nil
    }
}

public enum DirectorySize {
    public static func total(of path: String, on fileSystem: FileSystem, isCancelled: () -> Bool) -> Int64 {
        guard !isCancelled(), let entries = try? fileSystem.list(path) else { return 0 }
        var sum: Int64 = 0
        for entry in entries {
            if entry.isDirectory && !entry.isSymlink {
                sum += total(of: PosixPath.join(path, entry.name), on: fileSystem, isCancelled: isCancelled)
            } else if !entry.isSymlink {
                sum += entry.size
            }
        }
        return sum
    }
}
