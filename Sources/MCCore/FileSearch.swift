import Foundation

public struct SearchCriteria {
    public var namePattern: String
    public var content: String?
    public var caseSensitive: Bool
    public var useRegex: Bool

    public init(namePattern: String, content: String?, caseSensitive: Bool = false, useRegex: Bool = false) {
        self.namePattern = namePattern
        self.content = content
        self.caseSensitive = caseSensitive
        self.useRegex = useRegex
    }

    public func validate() throws {
        guard useRegex else { return }
        for expression in [namePattern, content ?? ""] where !expression.isEmpty {
            guard (try? NSRegularExpression(pattern: expression)) != nil else {
                throw FileError(localized("Ungültiger regulärer Ausdruck: %@", expression as NSString))
            }
        }
    }
}

private struct SearchMatcher {
    let name: (String) -> Bool
    let content: ((Data) -> Bool)?

    init?(_ criteria: SearchCriteria) {
        let caseSensitive = criteria.caseSensitive
        let namePattern = criteria.namePattern
        let text = criteria.content.flatMap { $0.isEmpty ? nil : $0 }
        if criteria.useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive]
            if namePattern.isEmpty {
                name = { _ in true }
            } else {
                guard let regex = try? NSRegularExpression(pattern: namePattern, options: options) else { return nil }
                name = { SearchMatcher.matches(regex, $0) }
            }
            if let text {
                guard let regex = try? NSRegularExpression(pattern: text, options: options) else { return nil }
                content = { SearchMatcher.matches(regex, String(decoding: $0, as: UTF8.self)) }
            } else {
                content = nil
            }
        } else {
            let pattern = namePattern.isEmpty ? "*" : namePattern
            let flags = caseSensitive ? 0 : FNM_CASEFOLD
            name = { fnmatch(pattern, $0, flags) == 0 }
            if let text {
                let needle = Data(text.utf8)
                content = caseSensitive
                    ? { $0.range(of: needle) != nil }
                    : { String(decoding: $0, as: UTF8.self).range(of: text, options: .caseInsensitive) != nil }
            } else {
                content = nil
            }
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}

public enum FileSearch {
    private static let maxContentSize: Int64 = 50_000_000

    public static func run(on fileSystem: FileSystem, root: String, criteria: SearchCriteria, isCancelled: () -> Bool, onMatch: (String) -> Void) {
        guard let matcher = SearchMatcher(criteria) else { return }
        visit(root, fileSystem, matcher, isCancelled, onMatch)
    }

    private static func visit(_ directory: String, _ fileSystem: FileSystem, _ matcher: SearchMatcher, _ isCancelled: () -> Bool, _ onMatch: (String) -> Void) {
        guard !isCancelled(), let entries = try? fileSystem.list(directory) else { return }
        for entry in entries {
            if isCancelled() { return }
            let path = PosixPath.join(directory, entry.name)
            let matchesName = matcher.name(entry.name)
            if entry.isDirectory {
                if matchesName && matcher.content == nil { onMatch(path) }
                if !entry.isSymlink { visit(path, fileSystem, matcher, isCancelled, onMatch) }
            } else if matchesName && (matcher.content == nil || contains(matcher.content!, in: path, entry, fileSystem)) {
                onMatch(path)
            }
        }
    }

    private static func contains(_ matches: (Data) -> Bool, in path: String, _ entry: FileEntry, _ fileSystem: FileSystem) -> Bool {
        guard fileSystem is LocalFileSystem, !entry.isSymlink, entry.size <= maxContentSize, let data = try? fileSystem.readAll(path) else { return false }
        return matches(data)
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
