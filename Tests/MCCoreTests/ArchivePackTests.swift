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

private func write(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

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

private func names(_ archive: String) throws -> [String] {
    try tar(["-tf", archive]).split(separator: "\n").map { name in
        var text = String(name)
        while text.hasPrefix("./") { text.removeFirst(2) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }.filter { !$0.isEmpty && $0 != "." }.sorted()
}

private func makeOperation() -> FileOperation {
    FileOperation(
        handlers: OperationHandlers(
            progress: { _ in },
            resolveConflict: { _ in .overwrite },
            resolveFailure: { _, _ in .abort }
        ),
        options: TransferOptions(overwriteRule: .overwrite)
    )
}

private func leftovers(_ root: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasPrefix(".") }
}

// Verschachtelt, damit die Tests nicht parallel zu den Stage-Ordner-Prüfungen von ArchiveWriteTests laufen.
extension ArchiveWriteTests {
@Suite struct ArchivePackTests {
    @Test(arguments: extensions) func missingArchiveIsEmpty(ext: String) throws {
        let root = try makeSandbox()
        let archive = root + "/neu." + ext
        let system = try ArchiveFileSystem(path: archive)
        #expect(try system.list("/").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive))
    }

    @Test(arguments: extensions) func createsArchiveWithFilesAndFolders(ext: String) throws {
        let root = try makeSandbox()
        try write("neu", to: root + "/in/new.txt")
        try write("1", to: root + "/in/folder/one.txt")
        try write("2", to: root + "/in/folder/inner/two.txt")
        let archive = root + "/out/neu." + ext
        try FileManager.default.createDirectory(atPath: root + "/out", withIntermediateDirectories: true)
        let system = try ArchiveFileSystem(path: archive)
        try makeOperation().copy([Transfer(source: root + "/in/new.txt", destination: "/new.txt"), Transfer(source: root + "/in/folder", destination: "/folder")], from: local, to: system)
        #expect(try names(archive) == ["folder", "folder/inner", "folder/inner/two.txt", "folder/one.txt", "new.txt"])
        #expect(try names(archive).filter { $0.contains("._") }.isEmpty)
        let fresh = try ArchiveFileSystem(path: archive)
        #expect(try fresh.list("/folder").map(\.name).sorted() == ["inner", "one.txt"])
        #expect(try fresh.readAll("/folder/inner/two.txt") == Data("2".utf8))
        #expect(try system.readAll("/new.txt") == Data("neu".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: archive)[.posixPermissions] as? Int
        #expect(permissions.map { $0 & 0o600 == 0o600 } == true)
        #expect(leftovers(root + "/out").isEmpty)
    }

    @Test(arguments: extensions) func addsToExistingArchive(ext: String) throws {
        let root = try makeSandbox()
        try write("eins", to: root + "/in/a.txt")
        try write("zwei", to: root + "/in/b.txt")
        let archive = root + "/test." + ext
        try makeOperation().copy([Transfer(source: root + "/in/a.txt", destination: "/a.txt")], from: local, to: try ArchiveFileSystem(path: archive))
        try makeOperation().copy([Transfer(source: root + "/in/b.txt", destination: "/b.txt")], from: local, to: try ArchiveFileSystem(path: archive))
        #expect(try names(archive) == ["a.txt", "b.txt"])
    }

    @Test func unwritableExtensionFailsWithoutFile() throws {
        let root = try makeSandbox()
        let archive = root + "/neu.rar"
        #expect(throws: (any Error).self) { try ArchiveFileSystem(path: archive) }
        #expect(!FileManager.default.fileExists(atPath: archive))
    }

    @Test func deletingFromMissingArchiveFails() throws {
        let root = try makeSandbox()
        let archive = root + "/neu.zip"
        #expect(throws: FileError.self) { try ArchiveRewriter.apply(ArchiveChanges(deletions: ["/a.txt"]), to: archive) }
        #expect(throws: FileError.self) { try ArchiveRewriter.apply(ArchiveChanges(renames: [(from: "/a", to: "/b")]), to: archive) }
        #expect(!FileManager.default.fileExists(atPath: archive))
        #expect(leftovers(root).isEmpty)
    }

    @Test(arguments: extensions) func rollbackLeavesNoFile(ext: String) throws {
        let root = try makeSandbox()
        let archive = root + "/neu." + ext
        let system = try ArchiveFileSystem(path: archive)
        system.beginTransaction()
        try system.writeAll(Data("neu".utf8), to: "/new.txt", permissions: 0o644)
        try system.makeDirectory("/dir")
        system.rollbackTransaction()
        try system.commitTransaction()
        #expect(!FileManager.default.fileExists(atPath: archive))
        #expect(leftovers(root).isEmpty)
        #expect(system.exists("/new.txt") == false)
    }

    @Test func failedCreationLeavesNoPartialFile() throws {
        let root = try makeSandbox()
        let archive = root + "/missing-folder/neu.zip"
        let system = try ArchiveFileSystem(path: archive)
        try write("x", to: root + "/in/a.txt")
        #expect(throws: (any Error).self) {
            try makeOperation().copy([Transfer(source: root + "/in/a.txt", destination: "/a.txt")], from: local, to: system)
        }
        #expect(!FileManager.default.fileExists(atPath: archive))
        #expect(leftovers(root).isEmpty)
    }
}
}
