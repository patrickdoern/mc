import Foundation
import Testing
@testable import MCCore

private let extensions = ["zip", "tar.gz", "7z"]
private let local = LocalFileSystem.shared

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ text: String, to path: String, modified: Date? = nil) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path) }
}

@discardableResult
private func tar(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

private func makeArchive(_ ext: String, in root: String, files: [String: String] = ["a.txt": "alt", "sub/b.txt": "bbb", "sub/deep/c.txt": "ccc", "keep.txt": "keep", "a b/[x].txt": "xx"]) throws -> String {
    let source = root + "/source"
    for (name, text) in files { try write(text, to: source + "/" + name) }
    let archive = root + "/test." + ext
    let options: [String: [String]] = ["zip": ["--format", "zip"], "tar": ["--format", "pax"], "tar.gz": ["--format", "pax", "-z"], "7z": ["--format", "7zip"], "tar.bz2": ["--format", "pax", "-j"], "tar.xz": ["--format", "pax", "-J"], "cpio": ["--format", "cpio"]]
    try tar(options[ext]! + ["-cf", archive, "-C", source, "."])
    try FileManager.default.removeItem(atPath: source)
    return archive
}

private func rawNames(_ archive: String) throws -> [String] {
    try tar(["-tf", archive]).split(separator: "\n").map { name in
        var text = String(name)
        while text.hasPrefix("./") { text.removeFirst(2) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }.filter { !$0.isEmpty && $0 != "." }
}

private func names(_ archive: String) throws -> [String] {
    try rawNames(archive).sorted()
}

private func content(_ archive: String, _ name: String) throws -> String {
    let member = try tar(["-tf", archive]).split(separator: "\n").map(String.init).first { $0 == name || $0 == "./" + name } ?? name
    return try tar(["-xOf", archive, member.map { "*?[]\\$".contains($0) ? "\\\($0)" : String($0) }.joined()])
}

private func stageFolders() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []).filter { $0.hasPrefix("mc-archive-stage-") }
}

private final class Counter {
    var asked = 0
}

private func makeOperation(_ rule: OverwriteRule = .overwrite, counter: Counter = Counter(), answer: ConflictChoice = .overwrite) -> FileOperation {
    FileOperation(
        handlers: OperationHandlers(
            progress: { _ in },
            resolveConflict: { _ in counter.asked += 1; return answer },
            resolveFailure: { _, _ in .abort }
        ),
        options: TransferOptions(overwriteRule: rule)
    )
}

private func copyIn(_ operation: FileOperation, _ items: [(String, String)], to archive: ArchiveFileSystem) throws {
    try operation.copy(items.map { Transfer(source: $0.0, destination: $0.1) }, from: local, to: archive)
}

@Suite(.serialized) struct ArchiveWriteTests {
    @Test(arguments: extensions + ["tar", "tar.xz"]) func copiesFileAndFolderIntoArchive(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try write("neu", to: root + "/in/new.txt")
        try write("1", to: root + "/in/folder/one.txt")
        try write("2", to: root + "/in/folder/inner/two.txt")
        let system = try ArchiveFileSystem(path: archive)
        try copyIn(makeOperation(), [(root + "/in/new.txt", "/sub/new.txt"), (root + "/in/folder", "/added")], to: system)
        #expect(try content(archive, "sub/new.txt") == "neu")
        #expect(try content(archive, "added/one.txt") == "1")
        #expect(try content(archive, "added/inner/two.txt") == "2")
        #expect(try content(archive, "sub/b.txt") == "bbb")
        #expect(try names(archive).filter { $0.contains("._") }.isEmpty)
        let fresh = try ArchiveFileSystem(path: archive)
        #expect(try fresh.list("/added").map(\.name).sorted() == ["inner", "one.txt"])
        #expect(try fresh.readAll("/added/inner/two.txt") == Data("2".utf8))
        #expect(try system.readAll("/sub/new.txt") == Data("neu".utf8))
        #expect(stageFolders().isEmpty)
    }

    @Test(arguments: extensions) func replacesExistingFileWithoutDuplicate(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try write("neu", to: root + "/b.txt")
        let system = try ArchiveFileSystem(path: archive)
        try copyIn(makeOperation(.overwrite), [(root + "/b.txt", "/sub/b.txt")], to: system)
        #expect(try rawNames(archive).filter { $0 == "sub/b.txt" }.count == 1)
        #expect(try content(archive, "sub/b.txt") == "neu")
        #expect(try system.stat("/sub/b.txt").size == 3)
    }

    @Test(arguments: extensions) func mergesExistingFolder(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try write("e", to: root + "/in/sub/extra.txt")
        try write("d", to: root + "/in/sub/deep/d.txt")
        let system = try ArchiveFileSystem(path: archive)
        try copyIn(makeOperation(), [(root + "/in/sub", "/sub")], to: system)
        let result = try names(archive)
        #expect(["sub/b.txt", "sub/extra.txt", "sub/deep/c.txt", "sub/deep/d.txt"].allSatisfy(result.contains))
        #expect(try rawNames(archive).filter { $0 == "sub" || $0 == "sub/deep" }.count == 2)
    }

    @Test(arguments: extensions) func copiesOutOfArchive(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().copy([Transfer(source: "/sub", destination: root + "/out")], from: system, to: local)
        #expect(try String(contentsOfFile: root + "/out/b.txt", encoding: .utf8) == "bbb")
        #expect(try String(contentsOfFile: root + "/out/deep/c.txt", encoding: .utf8) == "ccc")
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
    }

    @Test(arguments: extensions) func movesOutOfArchive(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().move([Transfer(source: "/sub", destination: root + "/out"), Transfer(source: "/a.txt", destination: root + "/a.txt")], from: system, to: local)
        #expect(try String(contentsOfFile: root + "/out/deep/c.txt", encoding: .utf8) == "ccc")
        #expect(try String(contentsOfFile: root + "/a.txt", encoding: .utf8) == "alt")
        #expect(try names(archive) == ["a b", "a b/[x].txt", "keep.txt"])
        #expect(system.exists("/sub") == false)
    }

    @Test(arguments: extensions) func deletesFileAndFolderWithContents(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().delete(["/a.txt", "/sub"], on: system, trash: false)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "keep.txt"])
        #expect(try system.list("/").map(\.name).sorted() == ["a b", "keep.txt"])
        #expect(stageFolders().isEmpty)
    }

    @Test(arguments: extensions + ["tar", "tar.xz"]) func renamesFileAndFolder(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().move([Transfer(source: "/a.txt", destination: "/b.txt"), Transfer(source: "/sub", destination: "/neu")], from: system, to: system)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "b.txt", "keep.txt", "neu", "neu/b.txt", "neu/deep", "neu/deep/c.txt"])
        #expect(try content(archive, "b.txt") == "alt")
        #expect(try content(archive, "neu/deep/c.txt") == "ccc")
    }

    @Test(arguments: extensions) func renamesDirectly(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try system.rename("/sub", "/neu")
        #expect(try names(archive).contains("neu/deep/c.txt"))
        try system.rename("/neu/b.txt", "/b.txt")
        #expect(try names(archive).contains("b.txt"))
        #expect(try content(archive, "b.txt") == "bbb")
    }

    @Test(arguments: extensions + ["tar.xz"]) func movesIntoExistingFolderWithMerge(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root, files: ["src/one.txt": "1", "src/deep/two.txt": "2", "src/same.txt": "neu", "dst/src/old.txt": "o", "dst/src/deep/three.txt": "3", "dst/src/same.txt": "alt", "keep.txt": "k"])
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().move([Transfer(source: "/src", destination: "/dst/src")], from: system, to: system)
        let result = try names(archive)
        #expect(result.filter { $0.hasPrefix("src") }.isEmpty)
        #expect(["dst/src/one.txt", "dst/src/old.txt", "dst/src/deep/two.txt", "dst/src/deep/three.txt", "dst/src/same.txt", "keep.txt"].allSatisfy(result.contains))
        #expect(try rawNames(archive).filter { $0 == "dst/src/same.txt" }.count == 1)
        #expect(try content(archive, "dst/src/same.txt") == "neu")
        #expect(try content(archive, "dst/src/deep/two.txt") == "2")
    }

    @Test(arguments: extensions) func movesFolderIntoOtherFolder(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().move([Transfer(source: "/sub", destination: "/a b/sub")], from: system, to: system)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "a b/sub", "a b/sub/b.txt", "a b/sub/deep", "a b/sub/deep/c.txt", "a.txt", "keep.txt"])
        #expect(try content(archive, "a b/sub/deep/c.txt") == "ccc")
    }

    @Test(arguments: extensions) func renamedFolderCanReceiveOriginalPathAgain(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        system.beginTransaction()
        try system.rename("/sub", "/other")
        try system.rename("/other/b.txt", "/sub-b.txt")
        try system.makeDirectory("/sub")
        try system.rename("/other/deep", "/sub/deep")
        try system.commitTransaction()
        let result = try names(archive)
        #expect(result == ["a b", "a b/[x].txt", "a.txt", "keep.txt", "other", "sub", "sub-b.txt", "sub/deep", "sub/deep/c.txt"])
        #expect(try content(archive, "sub-b.txt") == "bbb")
        #expect(try content(archive, "sub/deep/c.txt") == "ccc")
    }

    @Test(arguments: extensions) func createsFolders(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try system.makeDirectories("/sub/neu/tief")
        let result = try names(archive)
        #expect(result.contains("sub/neu") && result.contains("sub/neu/tief") && result.contains("sub/b.txt"))
        #expect(try system.stat("/sub/neu/tief").isDirectory)
    }

    @Test func copiesSymlinkIntoArchive() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("tar.gz", in: root)
        try write("t", to: root + "/target.txt")
        try local.makeSymlink(root + "/link", target: "target.txt")
        let system = try ArchiveFileSystem(path: archive)
        try copyIn(makeOperation(), [(root + "/link", "/link")], to: system)
        let fresh = try ArchiveFileSystem(path: archive)
        #expect(try fresh.stat("/link").isSymlink)
        #expect(try fresh.readLink("/link") == "target.txt")
    }

    @Test(arguments: extensions) func conflictRulesApplyInsideArchive(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let system = try ArchiveFileSystem(path: archive)
        try write("alt-lokal", to: root + "/b.txt", modified: Date(timeIntervalSince1970: 1_000_000_000))
        try copyIn(makeOperation(.ifNewer), [(root + "/b.txt", "/sub/b.txt")], to: system)
        #expect(try content(archive, "sub/b.txt") == "bbb")
        try copyIn(makeOperation(.skip), [(root + "/b.txt", "/sub/b.txt")], to: system)
        #expect(try content(archive, "sub/b.txt") == "bbb")
        try write("neuer", to: root + "/b.txt", modified: Date().addingTimeInterval(3600))
        try copyIn(makeOperation(.ifNewer), [(root + "/b.txt", "/sub/b.txt")], to: system)
        #expect(try content(archive, "sub/b.txt") == "neuer")
        let counter = Counter()
        try copyIn(makeOperation(.ask, counter: counter, answer: .skip), [(root + "/b.txt", "/sub/b.txt")], to: system)
        #expect(counter.asked == 1)
        #expect(try content(archive, "sub/b.txt") == "neuer")
    }

    @Test(arguments: extensions) func cancelledOperationLeavesArchiveUntouched(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        try write("z", to: root + "/in/z.txt")
        try write("neu", to: root + "/in/a.txt")
        let system = try ArchiveFileSystem(path: archive)
        #expect(throws: OperationAborted.self) {
            try copyIn(makeOperation(.ask, answer: .cancel), [(root + "/in/z.txt", "/z.txt"), (root + "/in/a.txt", "/a.txt")], to: system)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(system.exists("/z.txt") == false)
        #expect(try content(archive, "a.txt") == "alt")
        #expect(stageFolders().isEmpty)
    }

    @Test(arguments: extensions) func failedOperationLeavesArchiveUntouched(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        try write("z", to: root + "/z.txt")
        let system = try ArchiveFileSystem(path: archive)
        #expect(throws: OperationAborted.self) {
            try copyIn(makeOperation(), [(root + "/z.txt", "/z.txt"), (root + "/missing.txt", "/m.txt")], to: system)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(system.exists("/z.txt") == false)
        #expect(stageFolders().isEmpty)
    }

    @Test func unwritableFolderFailsAndKeepsArchive() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("zip", in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        try write("z", to: root + "/z.txt")
        let system = try ArchiveFileSystem(path: archive)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root) }
        #expect(throws: FileError.self) {
            try copyIn(makeOperation(), [(root + "/z.txt", "/z.txt")], to: system)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(system.exists("/z.txt") == false)
        #expect(try system.list("/").count == 4)
        #expect(stageFolders().isEmpty)
    }

    @Test func nonWritableFormatStaysReadOnly() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("cpio", in: root)
        #expect(ArchiveFileSystem.isArchive(archive) && !ArchiveFileSystem.isWritable(archive))
        let system = try ArchiveFileSystem(path: archive)
        let expected = localized("%@ ist ein Archiv und nur lesbar", "test.cpio" as NSString)
        func message(_ body: () throws -> Void) -> String? {
            do { try body() } catch { return error.localizedDescription }
            return nil
        }
        #expect(message { try system.makeDirectory("/neu") } == expected)
        #expect(message { try system.removeFile("/a.txt") } == expected)
        #expect(message { try system.removeDirectory("/sub") } == expected)
        #expect(message { try system.rename("/a.txt", "/b.txt") } == expected)
        #expect(message { try system.makeSymlink("/l", target: "a.txt") } == expected)
        #expect(message { try system.setModified("/a.txt", Date()) } == expected)
        #expect(message { try system.setPermissions("/a.txt", 0o600) } == expected)
        #expect(message { _ = try system.openWriter("/n.txt", permissions: 0o644) } == expected)
        #expect(message { try system.writeAll(Data("z".utf8), to: "/z.txt", permissions: 0o644) } == expected)
        system.beginTransaction()
        #expect(!system.hasPendingChanges)
        try system.commitTransaction()
        #expect(system.exists("/z.txt") == false)
    }

    @Test(arguments: extensions) func overlayIsVisibleBeforeCommit(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        let system = try ArchiveFileSystem(path: archive)
        #expect(!system.hasPendingChanges)
        system.beginTransaction()
        #expect(!system.hasPendingChanges)
        try system.writeAll(Data("neu".utf8), to: "/sub/new.txt", permissions: 0o600)
        #expect(system.hasPendingChanges)
        let entry = try system.stat("/sub/new.txt")
        #expect(entry.size == 3 && entry.permissions == 0o600)
        #expect(try system.list("/sub").map(\.name).contains("new.txt"))
        #expect(try system.readAll("/sub/new.txt") == Data("neu".utf8))
        try system.removeFile("/sub/new.txt")
        try system.removeFile("/a.txt")
        try system.rename("/keep.txt", "/kept.txt")
        #expect(system.exists("/sub/new.txt") == false)
        #expect(system.exists("/a.txt") == false)
        #expect(try system.readAll("/kept.txt") == Data("keep".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        try system.commitTransaction()
        #expect(try names(archive) == ["a b", "a b/[x].txt", "kept.txt", "sub", "sub/b.txt", "sub/deep", "sub/deep/c.txt"])
        #expect(!system.hasPendingChanges)
        #expect(stageFolders().isEmpty)
    }

    @Test(arguments: extensions) func rollbackRestoresOverlay(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        let system = try ArchiveFileSystem(path: archive)
        system.beginTransaction()
        try system.writeAll(Data("neu".utf8), to: "/new.txt", permissions: 0o644)
        try system.makeDirectory("/neu")
        try system.removeFile("/a.txt")
        system.rollbackTransaction()
        #expect(system.exists("/new.txt") == false)
        #expect(system.exists("/a.txt"))
        #expect(!system.hasPendingChanges)
        try system.commitTransaction()
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(stageFolders().isEmpty)
    }

    @Test func nestedTransactionsWriteOnce() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("zip", in: root)
        let system = try ArchiveFileSystem(path: archive)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        system.beginTransaction()
        system.beginTransaction()
        try system.makeDirectory("/neu")
        try system.commitTransaction()
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(system.hasPendingChanges)
        try system.makeDirectory("/zwei")
        try system.commitTransaction()
        #expect(try names(archive).contains("neu") && names(archive).contains("zwei"))
        #expect(!system.hasPendingChanges)
    }

    @Test func eachDirectActionWritesOnce() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("tar.gz", in: root)
        let system = try ArchiveFileSystem(path: archive)
        try system.makeDirectory("/neu")
        #expect(try names(archive).contains("neu"))
        try system.writeAll(Data("x".utf8), to: "/neu/x.txt", permissions: 0o644)
        #expect(try content(archive, "neu/x.txt") == "x")
        try system.removeFile("/neu/x.txt")
        #expect(try names(archive).contains("neu/x.txt") == false)
        try system.removeDirectory("/neu")
        #expect(try names(archive).contains("neu") == false)
        let writer = try system.openWriter("/abgebrochen.txt", permissions: 0o644)
        writer.abort()
        #expect(system.exists("/abgebrochen.txt") == false)
        #expect(stageFolders().isEmpty)
    }

    @Test func removingNonEmptyFolderIsRefused() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("zip", in: root)
        let system = try ArchiveFileSystem(path: archive)
        #expect(throws: FileError.self) { try system.removeDirectory("/sub") }
        #expect(throws: FileError.self) { try system.removeFile("/sub") }
        #expect(throws: FileError.self) { try system.rename("/sub", "/sub/deep/x") }
        #expect(throws: FileError.self) { try system.makeDirectory("/missing/child") }
        #expect(system.exists("/sub/b.txt"))
    }
}
