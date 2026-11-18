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

@Suite struct ArchiveTests {
    private func makeArchive(format: String) throws -> (root: String, archive: String) {
        let root = try makeSandbox()
        try write("alpha", to: root + "/src/a.txt")
        try write("beta [x]*", to: root + "/src/sub/b [1].txt")
        try FileManager.default.createSymbolicLink(atPath: root + "/src/link", withDestinationPath: "a.txt")
        let archive = root + "/test." + format
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.currentDirectoryURL = URL(fileURLWithPath: root + "/src")
        process.arguments = format == "zip" ? ["--format", "zip", "-cf", archive, "a.txt", "sub", "link"] : ["-cf", archive, "a.txt", "sub", "link"]
        try process.run()
        process.waitUntilExit()
        return (root, archive)
    }

    @Test(arguments: ["tar", "zip"]) func listsAndReadsMembers(format: String) throws {
        let (_, path) = try makeArchive(format: format)
        let archive = try ArchiveFileSystem(path: path)
        #expect(try archive.list("/").map(\.name).sorted() == ["a.txt", "link", "sub"])
        #expect(try archive.stat("/sub").isDirectory)
        #expect(try archive.list("/sub").map(\.name) == ["b [1].txt"])
        #expect(try archive.stat("/a.txt").size == 5)
        #expect(try String(decoding: archive.readAll("/a.txt"), as: UTF8.self) == "alpha")
        #expect(try String(decoding: archive.readAll("/sub/b [1].txt"), as: UTF8.self) == "beta [x]*")
    }

    @Test func exposesSymlinksAndIsReadOnly() throws {
        let (_, path) = try makeArchive(format: "tar")
        let archive = try ArchiveFileSystem(path: path)
        #expect(try archive.stat("/link").isSymlink)
        #expect(try archive.readLink("/link") == "a.txt")
        #expect(throws: FileError.self) { try archive.removeFile("/a.txt") }
        #expect(archive.exitLocation?.selecting == "test.tar")
    }

    @Test func copiesOutOfArchive() throws {
        let (root, path) = try makeArchive(format: "tar")
        let archive = try ArchiveFileSystem(path: path)
        let handlers = OperationHandlers(progress: { _ in }, resolveConflict: { _ in .overwrite }, resolveFailure: { _, _ in .abort })
        try FileOperation(handlers: handlers).copy([Transfer(source: "/sub", destination: root + "/out")], from: archive, to: LocalFileSystem.shared)
        #expect(try read(root + "/out/b [1].txt") == "beta [x]*")
    }

    @Test func recognisesArchiveNames() {
        #expect(ArchiveFileSystem.isArchive("Backup.TAR.GZ"))
        #expect(ArchiveFileSystem.isArchive("x.zip"))
        #expect(!ArchiveFileSystem.isArchive("notes.txt"))
    }
}

@Suite struct PanelizedTests {
    @Test func listsResultsRelativeToCommonRootAndCopiesFlat() throws {
        let root = try makeSandbox()
        try write("one", to: root + "/a/x.txt")
        try write("two", to: root + "/b/deep/y.txt")
        let results = PanelizedFileSystem(base: LocalFileSystem.shared, paths: [root + "/a/x.txt", root + "/b/deep/y.txt", root + "/gone.txt"], title: "Suche")
        #expect(try results.list("/").map(\.name).sorted() == ["a/x.txt", "b/deep/y.txt"])
        #expect(try String(decoding: results.readAll("/b/deep/y.txt"), as: UTF8.self) == "two")
        let handlers = OperationHandlers(progress: { _ in }, resolveConflict: { _ in .overwrite }, resolveFailure: { _, _ in .abort })
        try LocalFileSystem.shared.makeDirectory(root + "/out")
        try FileOperation(handlers: handlers).copy([Transfer(source: "/a/x.txt", destination: root + "/out/x.txt")], from: results, to: LocalFileSystem.shared)
        #expect(try read(root + "/out/x.txt") == "one")
        try FileOperation(handlers: handlers).delete(["/a/x.txt"], on: results, trash: false)
        #expect(!LocalFileSystem.shared.exists(root + "/a/x.txt"))
        #expect(results.exitLocation?.path == root)
        #expect(throws: FileError.self) { try results.makeDirectory("/new") }
    }
}

@Suite struct CompletionTests {
    let fileSystem = LocalFileSystem.shared

    private func complete(_ text: String, in root: String) -> Completion {
        CommandCompletion.complete(text: text, directory: root, fileSystem: fileSystem, home: "/nonexistent", searchPath: "/bin:/usr/bin")
    }

    @Test func completesFilesAndDirectories() throws {
        let root = try makeSandbox()
        try write("x", to: root + "/alpha.txt")
        try write("x", to: root + "/my file.txt")
        try write("x", to: root + "/alpine/inner.txt")
        let candidates = complete("ls al", in: root).candidates
        #expect(candidates == ["alpha.txt", "alpine/"])
        #expect(complete("ls al", in: root).commonPrefix == "alp")
        #expect(complete("cat my", in: root).candidates == ["my\\ file.txt"])
        #expect(complete("cat alpine/", in: root).candidates == ["alpine/inner.txt"])
        #expect(complete("cat my\\ f", in: root).candidates == ["my\\ file.txt"])
    }

    @Test func completesCommandsFromPath() {
        let candidates = complete("ech", in: "/tmp").candidates
        #expect(candidates.contains("echo"))
        #expect(complete("ex", in: "/tmp").candidates.contains("exit"))
    }
}

@Suite struct HexDumpTests {
    @Test func rendersOffsetsBytesAndAscii() {
        let text = HexDump.render(Data("Hello, hex dump!\n\u{0}".utf8))
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "00000000  48 65 6c 6c 6f 2c 20 68  65 78 20 64 75 6d 70 21  |Hello, hex dump!|")
        #expect(lines[1].hasPrefix("00000010  0a 00 "))
        #expect(lines[1].hasSuffix("|..|"))
    }

    @Test func truncatesLargeInput() {
        #expect(HexDump.render(Data(repeating: 0x41, count: 100), limit: 32).contains("gekürzt: 32 von 100"))
    }
}

@Suite struct NameMaskTests {
    @Test func replacesStemAndExtension() {
        #expect(NameMask.apply("*.bak", to: "foo.txt") == "foo.bak")
        #expect(NameMask.apply("*.*", to: "foo.txt") == "foo.txt")
        #expect(NameMask.apply("neu_*", to: "foo.txt") == "neu_foo.txt")
        #expect(NameMask.apply("*.old.*", to: "foo.txt") == "foo.old.txt")
        #expect(NameMask.apply("*.bak", to: "Makefile") == "Makefile.bak")
        #expect(NameMask.apply("*.bak", to: ".zshrc") == ".zshrc.bak")
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
