import Foundation

public struct ArchiveChanges {
    public var additions: [(staged: String, archive: String)]
    public var deletions: [String]
    public var renames: [(from: String, to: String)]
    public var newDirectories: [String]

    public init(additions: [(staged: String, archive: String)] = [], deletions: [String] = [], renames: [(from: String, to: String)] = [], newDirectories: [String] = []) {
        self.additions = additions
        self.deletions = deletions
        self.renames = renames
        self.newDirectories = newDirectories
    }

    var isEmpty: Bool { additions.isEmpty && deletions.isEmpty && renames.isEmpty && newDirectories.isEmpty }
}

public enum ArchiveRewriter {
    private static let bsdtar = "/usr/bin/bsdtar"
    private static let formats: [(suffixes: [String], arguments: [String])] = [
        ([".zip", ".jar", ".war"], ["--format", "zip"]),
        ([".tar"], ["--format", "pax"]),
        ([".tgz", ".tar.gz"], ["--format", "pax", "-z"]),
        ([".tbz", ".tbz2", ".tar.bz2"], ["--format", "pax", "-j"]),
        ([".txz", ".tar.xz"], ["--format", "pax", "-J"]),
        ([".7z"], ["--format", "7zip"])
    ]
    private static let delimiters = Array("|#%@~!;:+")

    static func formatArguments(for name: String) -> [String]? {
        let lower = name.lowercased()
        return formats.first { $0.suffixes.contains { lower.hasSuffix($0) } }?.arguments
    }

    public static func apply(_ changes: ArchiveChanges, to archivePath: String) throws {
        let name = PosixPath.name(archivePath)
        guard let format = formatArguments(for: name) else { throw failure(name, nil) }
        guard !changes.isEmpty else { return }
        let fileManager = FileManager.default
        let id = UUID().uuidString
        let folder = PosixPath.parent(archivePath)
        let work = NSTemporaryDirectory() + "mc-archive-" + id
        var temporaries = [work]
        defer { for path in temporaries { try? fileManager.removeItem(atPath: path) } }
        do {
            try fileManager.createDirectory(atPath: work, withIntermediateDirectories: true)
            var current = archivePath
            var additions = changes.additions
            for (index, directory) in changes.newDirectories.enumerated() {
                let empty = work + "/dir\(index)"
                try fileManager.createDirectory(atPath: empty, withIntermediateDirectories: true)
                additions.append((empty, directory))
            }
            let base = [format, ["--no-mac-metadata"]].flatMap { $0 }
            if !changes.deletions.isEmpty || !changes.renames.isEmpty {
                let output = folder + "/." + name + ".mc-tmp-" + id + "-1"
                temporaries.append(output)
                let patterns = changes.deletions.flatMap { prefixPatterns(for: $0) }
                let list = work + "/delete.txt"
                try write(patterns, to: list)
                var arguments = base + ["-cf", output, "-X", list]
                for (from, to) in changes.renames { arguments += try substitutions(from: unrooted(from), to: unrooted(to), source: .archive) }
                try run(arguments + ["@" + current], archive: name)
                current = output
            }
            if !additions.isEmpty {
                let output = folder + "/." + name + ".mc-tmp-" + id + "-2"
                temporaries.append(output)
                var replaced: [String] = []
                var rules: [String] = []
                for (staged, target) in additions {
                    replaced += try replacedPatterns(staged: staged, target: unrooted(target))
                    rules += try substitutions(from: staged, to: unrooted(target), source: .staged)
                }
                let list = work + "/replace.txt"
                try write(replaced, to: list)
                try run(base + ["-cf", output, "-X", list] + rules + ["@" + current] + additions.map(\.staged), archive: name)
                current = output
            }
            if let permissions = try? fileManager.attributesOfItem(atPath: archivePath)[.posixPermissions] {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: current)
            }
            guard rename(current, archivePath) == 0 else { throw failure(name, String(cString: strerror(errno))) }
        } catch let error as FileError {
            throw error
        } catch {
            throw failure(name, error.localizedDescription)
        }
    }

    private enum Source { case archive, staged }

    private static func unrooted(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func write(_ patterns: [String], to path: String) throws {
        try (patterns.map { $0 + "\n" }.joined()).write(toFile: path, atomically: false, encoding: .utf8)
    }

    private static func glob(_ text: String) -> String {
        text.map { "\\*?[]$^".contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    private static func basic(_ text: String) -> String {
        text.map { "\\.*[^$".contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    private static func prefixPatterns(for path: String) -> [String] {
        let escaped = glob(unrooted(path))
        return ["^./" + escaped, "^" + escaped]
    }

    private static func exactPatterns(for path: String) -> [String] {
        prefixPatterns(for: path).map { $0 + "$" }
    }

    private static func replacedPatterns(staged: String, target: String) throws -> [String] {
        var result = exactPatterns(for: target)
        let fileManager = FileManager.default
        guard (try? fileManager.attributesOfItem(atPath: staged))?[.type] as? FileAttributeType == .typeDirectory,
              let enumerator = fileManager.enumerator(atPath: staged) else { return result }
        for case let relative as String in enumerator { result += exactPatterns(for: target + "/" + relative) }
        return result
    }

    private static func substitutions(from: String, to: String, source: Source) throws -> [String] {
        guard let delimiter = delimiters.first(where: { !from.contains($0) && !to.contains($0) }).map(String.init) else {
            throw FileError(localized("Archiv lässt sich nicht schreiben: %@", to as NSString))
        }
        let prefix = source == .archive ? #"^\(\./\)\{0,1\}"# : "^"
        let keep = source == .archive ? #"\1"# : ""
        let target = to.replacingOccurrences(of: "\\", with: "\\\\")
        func rule(_ pattern: String, _ end: String, _ replacement: String) -> [String] {
            ["-s", delimiter + prefix + basic(pattern) + end + delimiter + keep + replacement + delimiter]
        }
        return rule(from, "$", target) + rule(from + "/", "", target + "/")
    }

    private static func failure(_ name: String, _ detail: String?) -> FileError {
        let suffix = detail.map { ": " + $0 } ?? ""
        return FileError(localized("Archiv lässt sich nicht schreiben: %@", (name + suffix) as NSString))
    }

    private static func run(_ arguments: [String], archive name: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bsdtar)
        process.arguments = arguments
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init)
            throw failure(name, line)
        }
    }
}
