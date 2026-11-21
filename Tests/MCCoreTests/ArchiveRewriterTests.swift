import Foundation
import Testing
@testable import MCCore

private let extensions = ["zip", "tar", "tar.gz", "7z", "tar.bz2", "tar.xz"]

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
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
    let options: [String: [String]] = ["zip": ["--format", "zip"], "tar": ["--format", "pax"], "tar.gz": ["--format", "pax", "-z"], "7z": ["--format", "7zip"], "tar.bz2": ["--format", "pax", "-j"], "tar.xz": ["--format", "pax", "-J"]]
    try tar(options[ext]! + ["-cf", archive, "-C", source, "."])
    try FileManager.default.removeItem(atPath: source)
    return archive
}

private func names(_ archive: String) throws -> [String] {
    try tar(["-tf", archive]).split(separator: "\n").map { name in
        var text = String(name)
        while text.hasPrefix("./") { text.removeFirst(2) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }.filter { !$0.isEmpty && $0 != "." }.sorted()
}

private func content(_ archive: String, _ name: String) throws -> String {
    let member = try tar(["-tf", archive]).split(separator: "\n").map(String.init).first { $0 == name || $0 == "./" + name } ?? name
    return try tar(["-xOf", archive, member.map { "*?[]\\$".contains($0) ? "\\\($0)" : String($0) }.joined()])
}

private func staging(_ root: String, _ files: [String: String]) throws -> String {
    let path = root + "/staging"
    for (name, text) in files { try write(text, to: path + "/" + name) }
    return path
}

private func leftovers(_ root: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: root).filter { $0.contains("mc-tmp") }
}

@Suite struct ArchiveRewriterTests {
    @Test(arguments: extensions) func addsFileAndDirectoryWithContents(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let stage = try staging(root, ["new.txt": "neu", "folder/one.txt": "1", "folder/inner/two.txt": "2"])
        try ArchiveRewriter.apply(ArchiveChanges(additions: [(stage + "/new.txt", "/sub/new.txt"), (stage + "/folder", "/added")]), to: archive)
        let result = try names(archive)
        #expect(result.contains("sub/new.txt") && result.contains("added") && result.contains("added/inner/two.txt"))
        #expect(try content(archive, "sub/new.txt") == "neu")
        #expect(try content(archive, "added/one.txt") == "1")
        #expect(try content(archive, "added/inner/two.txt") == "2")
        #expect(try content(archive, "sub/b.txt") == "bbb")
        #expect(try leftovers(root).isEmpty)
    }

    @Test(arguments: extensions) func replacingKeepsSingleEntry(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let stage = try staging(root, ["a.txt": "neu", "sub/b.txt": "BBB"])
        try ArchiveRewriter.apply(ArchiveChanges(additions: [(stage + "/a.txt", "/a.txt"), (stage + "/sub", "/sub")]), to: archive)
        let result = try names(archive)
        #expect(result.filter { $0 == "a.txt" }.count == 1)
        #expect(result.filter { $0 == "sub" }.count == 1)
        #expect(result.filter { $0 == "sub/b.txt" }.count == 1)
        #expect(try content(archive, "a.txt") == "neu")
        #expect(try content(archive, "sub/b.txt") == "BBB")
        #expect(try content(archive, "sub/deep/c.txt") == "ccc")
    }

    @Test(arguments: extensions) func deletesFileAndDirectoryWithContents(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try ArchiveRewriter.apply(ArchiveChanges(deletions: ["/a.txt", "/sub"]), to: archive)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "keep.txt"])
    }

    @Test(arguments: extensions) func exactDeletionKeepsMovedChildren(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try ArchiveRewriter.apply(ArchiveChanges(exactDeletions: ["/sub"], renames: [("/sub/b.txt", "/b.txt")]), to: archive)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "a.txt", "b.txt", "keep.txt", "sub/deep", "sub/deep/c.txt"])
    }

    @Test(arguments: extensions) func renamesFileAndDirectoryWithContents(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try ArchiveRewriter.apply(ArchiveChanges(renames: [("/a.txt", "/sub/moved.txt"), ("/sub", "/neu")]), to: archive)
        #expect(try names(archive) == ["a b", "a b/[x].txt", "keep.txt", "neu", "neu/b.txt", "neu/deep", "neu/deep/c.txt", "sub/moved.txt"])
    }

    @Test(arguments: extensions) func createsEmptyDirectory(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        try ArchiveRewriter.apply(ArchiveChanges(newDirectories: ["/sub/leer"]), to: archive)
        let result = try names(archive)
        #expect(result.contains("sub/leer"))
        #expect(result.contains("sub/b.txt"))
    }

    @Test(arguments: ["zip", "tar.gz", "7z"]) func handlesSpecialCharacters(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let stage = try staging(root, ["x y [1] $a&b.txt": "sp"])
        try ArchiveRewriter.apply(ArchiveChanges(additions: [(stage + "/x y [1] $a&b.txt", "/a b/x y [1] $a&b.txt")], deletions: ["/a b/[x].txt"], renames: [("/keep.txt", "/k [2] & #.txt")]), to: archive)
        #expect(try names(archive).filter { $0.hasPrefix("a b") || $0.hasPrefix("k ") || $0 == "keep.txt" } == ["a b", "a b/x y [1] $a&b.txt", "k [2] & #.txt"])
        #expect(try content(archive, "k [2] & #.txt") == "keep")
        #expect(try content(archive, "a b/x y [1] $a&b.txt") == "sp")
    }

    @Test(arguments: extensions) func appliesSeveralChangesAtOnce(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let stage = try staging(root, ["keep.txt": "ersetzt", "extra.txt": "extra"])
        try ArchiveRewriter.apply(ArchiveChanges(
            additions: [(stage + "/keep.txt", "/keep.txt"), (stage + "/extra.txt", "/neu/extra.txt")],
            deletions: ["/sub/deep"],
            renames: [("/a.txt", "/b.txt")],
            newDirectories: ["/leer"]
        ), to: archive)
        let result = try names(archive)
        #expect(result == ["a b", "a b/[x].txt", "b.txt", "keep.txt", "leer", "neu/extra.txt", "sub", "sub/b.txt"])
        #expect(try content(archive, "keep.txt") == "ersetzt")
        #expect(try content(archive, "b.txt") == "alt")
    }

    @Test(arguments: ["zip", "tar", "7z"]) func writesNoAppleDoubleEntriesAndKeepsAttributes(ext: String) throws {
        let root = try makeSandbox()
        let archive = try makeArchive(ext, in: root)
        let stage = try staging(root, ["run.sh": "#!/bin/sh"])
        let file = stage + "/run.sh"
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o755, .modificationDate: date], ofItemAtPath: file)
        let attribute = Process()
        attribute.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        attribute.arguments = ["-w", "user.test", "1", file]
        try attribute.run()
        attribute.waitUntilExit()
        try ArchiveRewriter.apply(ArchiveChanges(additions: [(file, "/run.sh")]), to: archive)
        #expect(try names(archive).allSatisfy { !PosixPath.name($0).hasPrefix("._") })
        let output = root + "/out"
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        try tar(["-xf", archive, "-C", output])
        let attributes = try FileManager.default.attributesOfItem(atPath: output + "/run.sh")
        #expect(attributes[.posixPermissions] as? Int == 0o755)
        #expect(attributes[.modificationDate] as? Date == date)
    }

    @Test func readOnlyFolderLeavesArchiveUntouched() throws {
        let root = try makeSandbox()
        let archive = try makeArchive("zip", in: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: archive))
        let stage = try staging(root, ["new.txt": "neu"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root) }
        #expect {
            try ArchiveRewriter.apply(ArchiveChanges(additions: [(stage + "/new.txt", "/new.txt")], deletions: ["/a.txt"]), to: archive)
        } throws: { error in
            (error as? FileError)?.message.hasPrefix("Archiv lässt sich nicht schreiben: test.zip") == true
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root)
        #expect(try Data(contentsOf: URL(fileURLWithPath: archive)) == before)
        #expect(try leftovers(root).isEmpty)
    }

    @Test func detectsWritableFormats() {
        for name in ["a.zip", "a.jar", "a.war", "a.tar", "a.tgz", "a.tar.gz", "a.tbz", "a.tbz2", "a.tar.bz2", "a.txz", "a.tar.xz", "a.7z", "A.ZIP", "B.Tar.GZ", "c.7Z", "d.TXZ"] {
            #expect(ArchiveFileSystem.isWritable(name), Comment(rawValue: name))
        }
        for name in ["a.rar", "a.iso", "a.tar.zst", "a.txt", "a.cpio", "a.xar", "zip"] {
            #expect(!ArchiveFileSystem.isWritable(name), Comment(rawValue: name))
        }
    }
}
