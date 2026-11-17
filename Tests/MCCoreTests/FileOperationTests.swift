import Foundation
import Testing
@testable import MCCore

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func makeOperation(conflict: ConflictChoice = .overwrite) -> FileOperation {
    FileOperation(handlers: OperationHandlers(
        progress: { _ in },
        resolveConflict: { _ in conflict },
        resolveFailure: { _, _ in .abort }
    ))
}

private func write(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

@Suite struct FileOperationTests {
    let fileSystem = LocalFileSystem.shared

    @Test func copiesDirectoryTreeIncludingSymlinks() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/src/a.txt")
        try write("b", to: root + "/src/sub/b.txt")
        try fileSystem.makeSymlink(root + "/src/link", target: "a.txt")
        try makeOperation().copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/dst/a.txt") == "a")
        #expect(try read(root + "/dst/sub/b.txt") == "b")
        #expect(try fileSystem.readLink(root + "/dst/link") == "a.txt")
    }

    @Test func skipKeepsExistingFile() throws {
        let root = try makeSandbox()
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        try makeOperation(conflict: .skip).copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/b.txt") == "old")
    }

    @Test func overwriteReplacesExistingFile() throws {
        let root = try makeSandbox()
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        try makeOperation().copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/b.txt") == "new")
    }

    @Test func refusesCopyingFolderIntoItself() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/src/a.txt")
        var failures = 0
        let operation = FileOperation(handlers: OperationHandlers(
            progress: { _ in },
            resolveConflict: { _ in .overwrite },
            resolveFailure: { _, _ in failures += 1; return .skip }
        ))
        try operation.copy([Transfer(source: root + "/src", destination: root + "/src/inner")], from: fileSystem, to: fileSystem)
        #expect(failures == 1)
        #expect(!fileSystem.exists(root + "/src/inner"))
    }

    @Test func moveMergesIntoExistingDirectory() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/src/a.txt")
        try write("keep", to: root + "/dst/keep.txt")
        try makeOperation().move([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/dst/a.txt") == "a")
        #expect(try read(root + "/dst/keep.txt") == "keep")
        #expect(!fileSystem.exists(root + "/src"))
    }

    @Test func moveRenamesWhenDestinationIsFree() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/a.txt")
        try makeOperation().move([Transfer(source: root + "/a.txt", destination: root + "/renamed.txt")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/renamed.txt") == "a")
        #expect(!fileSystem.exists(root + "/a.txt"))
    }

    @Test func deleteRemovesTreeWithoutTrash() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/src/sub/a.txt")
        try makeOperation().delete([root + "/src"], on: fileSystem, trash: false)
        #expect(!fileSystem.exists(root + "/src"))
    }

    @Test func cancelAbortsOperation() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/a.txt")
        let operation = makeOperation()
        operation.cancel()
        #expect(throws: OperationAborted.self) {
            try operation.copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: fileSystem, to: fileSystem)
        }
        #expect(!fileSystem.exists(root + "/b.txt"))
    }

    @Test func makesNestedDirectories() throws {
        let root = try makeSandbox()
        try fileSystem.makeDirectories(root + "/a/b/c")
        #expect(try fileSystem.stat(root + "/a/b/c").isDirectory)
        try write("x", to: root + "/file")
        #expect(throws: FileError.self) { try fileSystem.makeDirectories(root + "/file/sub") }
    }

    @Test func listsEntriesWithKinds() throws {
        let root = try makeSandbox()
        try write("abc", to: root + "/file.txt")
        try fileSystem.makeDirectory(root + "/dir")
        let entries = Dictionary(uniqueKeysWithValues: try fileSystem.list(root).map { ($0.name, $0) })
        #expect(entries["file.txt"]?.size == 3)
        #expect(entries["dir"]?.isDirectory == true)
    }
}

@Suite struct SearchTests {
    let fileSystem = LocalFileSystem.shared

    @Test func findsByNameAndContent() throws {
        let root = try makeSandbox()
        try write("needle in text", to: root + "/a/one.txt")
        try write("nothing", to: root + "/a/b/two.txt")
        try write("needle", to: root + "/c.log")
        var byName: [String] = []
        FileSearch.run(on: fileSystem, root: root, criteria: SearchCriteria(namePattern: "*.TXT", content: nil), isCancelled: { false }) { byName.append($0) }
        #expect(byName.sorted() == [root + "/a/b/two.txt", root + "/a/one.txt"])
        var byContent: [String] = []
        FileSearch.run(on: fileSystem, root: root, criteria: SearchCriteria(namePattern: "*", content: "needle"), isCancelled: { false }) { byContent.append($0) }
        #expect(byContent.sorted() == [root + "/a/one.txt", root + "/c.log"])
    }

    @Test func sumsDirectorySizesAndChangesPermissions() throws {
        let root = try makeSandbox()
        try write("12345", to: root + "/d/a")
        try write("123", to: root + "/d/s/b")
        #expect(DirectorySize.total(of: root + "/d", on: fileSystem, isCancelled: { false }) == 8)
        try fileSystem.setPermissions(root + "/d/a", 0o600)
        #expect(try fileSystem.stat(root + "/d/a").permissions == 0o600)
        try fileSystem.makeHardLink(root + "/d/hard", to: root + "/d/a")
        #expect(try String(contentsOfFile: root + "/d/hard", encoding: .utf8) == "12345")
    }
}

@Suite struct PosixPathTests {
    @Test func computesRelativePaths() {
        #expect(PosixPath.relative(from: "/a/b", to: "/a/c/d") == "../c/d")
        #expect(PosixPath.relative(from: "/a", to: "/a/b") == "b")
        #expect(PosixPath.relative(from: "/a", to: "/a") == ".")
    }

    @Test func resolvesRelativeAndHomePaths() {
        #expect(PosixPath.resolve("../x", relativeTo: "/a/b", home: "/h") == "/a/x")
        #expect(PosixPath.resolve("~/y", relativeTo: "/a", home: "/h") == "/h/y")
        #expect(PosixPath.resolve("/", relativeTo: "/a", home: "/h") == "/")
        #expect(PosixPath.parent("/a") == "/")
        #expect(PosixPath.name("/a/b.txt") == "b.txt")
    }
}

@Suite struct SyntaxHighlightingTests {
    private func kinds(_ text: String, _ language: String) -> [(String, TokenKind)] {
        let string = text as NSString
        return SyntaxHighlighter.tokens(in: text, language: language).map { (string.substring(with: $0.range), $0.kind) }
    }

    @Test func detectsLanguages() {
        #expect(SyntaxHighlighter.languageName(forFile: "main.swift", firstLine: "") == "swift")
        #expect(SyntaxHighlighter.languageName(forFile: "run", firstLine: "#!/usr/bin/env python3") == "python")
        #expect(SyntaxHighlighter.languageName(forFile: "notes.txt", firstLine: "") == nil)
    }

    @Test func commentMarkersInsideStringsStayStrings() {
        let tokens = kinds(#"let url = "http://x" // note"#, "swift")
        #expect(tokens.contains { $0.0 == #""http://x""# && $0.1 == .string })
        #expect(tokens.contains { $0.0 == "// note" && $0.1 == .comment })
        #expect(tokens.contains { $0.0 == "let" && $0.1 == .keyword })
    }

    @Test func highlightsJsonKeysAndNumbers() {
        let tokens = kinds(#"{"name": "x", "count": 42}"#, "json")
        #expect(tokens.contains { $0.0 == #""name""# && $0.1 == .property })
        #expect(tokens.contains { $0.0 == "42" && $0.1 == .number })
    }

    @Test func unterminatedBlockCommentRunsToEnd() {
        #expect(kinds("a /* open\nstill", "c").contains { $0.1 == .comment && $0.0.hasSuffix("still") })
    }
}
