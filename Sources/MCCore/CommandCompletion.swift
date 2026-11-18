import Foundation

public struct Completion {
    public let word: String
    public let candidates: [String]

    public var commonPrefix: String {
        guard var prefix = candidates.first else { return word }
        for candidate in candidates.dropFirst() {
            prefix = String(zip(prefix, candidate).prefix { $0 == $1 }.map(\.0))
        }
        return prefix
    }
}

public enum CommandCompletion {
    private static let escaped = Set(" '\"()&;$`\\!#*?[]{}|<>~")
    private static let builtins = ["cd", "exit"]

    public static func complete(text: String, directory: String, fileSystem: FileSystem, home: String, searchPath: String) -> Completion {
        let (before, word) = split(text)
        let raw = unescape(word)
        if before.trimmingCharacters(in: .whitespaces).isEmpty, !raw.contains("/"), !raw.hasPrefix("~") {
            return Completion(word: word, candidates: commands(startingWith: raw, in: searchPath).map(escape))
        }
        let slash = raw.lastIndex(of: "/")
        let directoryPart = slash.map { String(raw[...$0]) } ?? ""
        let prefix = slash.map { String(raw[raw.index(after: $0)...]) } ?? raw
        let base = directoryPart.isEmpty ? directory : PosixPath.resolve(directoryPart, relativeTo: directory, home: home)
        let entries = (try? fileSystem.list(base)) ?? []
        let names = entries
            .filter { $0.name.hasPrefix(prefix) && (prefix.hasPrefix(".") || !$0.isHidden) }
            .map { directoryPart + $0.name + ($0.isDirectory ? "/" : "") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Completion(word: word, candidates: names.map(escape))
    }

    public static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if escaped.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var pending = false
        for character in text {
            if pending || character != "\\" {
                result.append(character)
                pending = false
            } else {
                pending = true
            }
        }
        return result
    }

    private static func split(_ text: String) -> (before: String, word: String) {
        var wordStart = text.startIndex
        var pending = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if pending {
                pending = false
            } else if character == "\\" {
                pending = true
            } else if character == " " {
                wordStart = text.index(after: index)
            }
            index = text.index(after: index)
        }
        return (String(text[..<wordStart]), String(text[wordStart...]))
    }

    private static func commands(startingWith prefix: String, in searchPath: String) -> [String] {
        var names = Set(builtins.filter { $0.hasPrefix(prefix) })
        for directory in searchPath.split(separator: ":") {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: String(directory))) ?? [] where name.hasPrefix(prefix) {
                if FileManager.default.isExecutableFile(atPath: directory + "/" + name) { names.insert(name) }
            }
        }
        return names.sorted()
    }
}
