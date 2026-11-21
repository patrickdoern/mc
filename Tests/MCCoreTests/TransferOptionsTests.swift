import Foundation
import Testing
@testable import MCCore

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ text: String, to path: String, modified: Date? = nil, permissions: Int? = nil) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    var attributes: [FileAttributeKey: Any] = [:]
    if let modified { attributes[.modificationDate] = modified }
    if let permissions { attributes[.posixPermissions] = permissions }
    if !attributes.isEmpty { try FileManager.default.setAttributes(attributes, ofItemAtPath: path) }
}

private func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

private final class Failures {
    var paths: [String] = []
}

private final class OperationBox {
    var operation: FileOperation?
}

private func makeOperation(_ options: TransferOptions, failures: Failures = Failures()) -> FileOperation {
    let box = OperationBox()
    let operation = FileOperation(
        handlers: OperationHandlers(
            progress: { if $0.filesDone > 200 { box.operation?.cancel() } },
            resolveConflict: { _ in .overwrite },
            resolveFailure: { path, _ in failures.paths.append(path); return .skip }
        ),
        options: options
    )
    box.operation = operation
    return operation
}

private func fileCount(_ path: String) -> Int {
    (FileManager.default.enumerator(atPath: path)?.allObjects.count) ?? 0
}

@Suite struct TransferOptionsTests {
    let fileSystem = LocalFileSystem.shared
    let yearAgo = Date(timeIntervalSinceNow: -365 * 86400)

    private func copy(_ operation: FileOperation, _ source: String, to destination: String) throws {
        try operation.copy([Transfer(source: source, destination: destination)], from: fileSystem, to: fileSystem)
    }

    @Test func withoutPreserveFileGetsCurrentTimeAndKeepsExecutableBit() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("run", to: root + "/a.sh", modified: yearAgo, permissions: 0o755)
        try copy(makeOperation(TransferOptions(preserveAttributes: false)), root + "/a.sh", to: root + "/b.sh")
        let entry = try fileSystem.stat(root + "/b.sh")
        #expect(entry.modified! > yearAgo + 86400)
        #expect(entry.permissions & 0o111 == 0o111)
        #expect(try read(root + "/b.sh") == "run")
    }

    @Test func withPreserveFileKeepsTime() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("run", to: root + "/a.sh", modified: yearAgo, permissions: 0o755)
        try copy(makeOperation(TransferOptions(preserveAttributes: true)), root + "/a.sh", to: root + "/b.sh")
        let entry = try fileSystem.stat(root + "/b.sh")
        #expect(abs(entry.modified!.timeIntervalSince(yearAgo)) < 1)
        #expect(entry.permissions & 0o111 == 0o111)
    }

    @Test func withoutPreserveFolderGetsCurrentTime() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/src/sub/a.sh", modified: yearAgo, permissions: 0o755)
        try FileManager.default.setAttributes([.modificationDate: yearAgo], ofItemAtPath: root + "/src/sub")
        try FileManager.default.setAttributes([.modificationDate: yearAgo], ofItemAtPath: root + "/src")
        try copy(makeOperation(TransferOptions(preserveAttributes: false)), root + "/src", to: root + "/dst")
        #expect(try fileSystem.stat(root + "/dst").modified! > yearAgo + 86400)
        #expect(try fileSystem.stat(root + "/dst/sub").modified! > yearAgo + 86400)
        let file = try fileSystem.stat(root + "/dst/sub/a.sh")
        #expect(file.modified! > yearAgo + 86400)
        #expect(file.permissions & 0o111 == 0o111)
    }

    @Test func withPreserveFolderKeepsTime() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/src/sub/a.txt", modified: yearAgo)
        try FileManager.default.setAttributes([.modificationDate: yearAgo], ofItemAtPath: root + "/src/sub")
        try FileManager.default.setAttributes([.modificationDate: yearAgo], ofItemAtPath: root + "/src")
        try copy(makeOperation(TransferOptions(preserveAttributes: true)), root + "/src", to: root + "/dst")
        #expect(abs(try fileSystem.stat(root + "/dst").modified!.timeIntervalSince(yearAgo)) < 1)
        #expect(abs(try fileSystem.stat(root + "/dst/sub").modified!.timeIntervalSince(yearAgo)) < 1)
        #expect(abs(try fileSystem.stat(root + "/dst/sub/a.txt").modified!.timeIntervalSince(yearAgo)) < 1)
    }

    @Test func symlinkToFileIsCopiedAsLinkByDefault() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("content", to: root + "/target.txt")
        try fileSystem.makeSymlink(root + "/link", target: "target.txt")
        try copy(makeOperation(TransferOptions()), root + "/link", to: root + "/copy")
        #expect(try fileSystem.stat(root + "/copy").isSymlink)
    }

    @Test func followedSymlinkToFileBecomesRegularFile() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("content", to: root + "/target.txt", permissions: 0o755)
        try fileSystem.makeSymlink(root + "/link", target: "target.txt")
        try copy(makeOperation(TransferOptions(followSymlinks: true)), root + "/link", to: root + "/copy")
        let entry = try fileSystem.stat(root + "/copy")
        #expect(!entry.isSymlink)
        #expect(entry.size == 7)
        #expect(entry.permissions & 0o111 == 0o111)
        #expect(try read(root + "/copy") == "content")
    }

    @Test func followedSymlinkToFolderIsCopiedWithContent() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("inner", to: root + "/dir/inner.txt")
        try fileSystem.makeSymlink(root + "/link", target: "dir")
        try copy(makeOperation(TransferOptions(followSymlinks: true)), root + "/link", to: root + "/copy")
        let entry = try fileSystem.stat(root + "/copy")
        #expect(entry.isDirectory && !entry.isSymlink)
        #expect(try read(root + "/copy/inner.txt") == "inner")
    }

    @Test func followedSymlinkInsideFolderBecomesRegularFile() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("content", to: root + "/outside.txt")
        try write("x", to: root + "/src/a.txt")
        try fileSystem.makeSymlink(root + "/src/link", target: "../outside.txt")
        try copy(makeOperation(TransferOptions(followSymlinks: true)), root + "/src", to: root + "/dst")
        #expect(!(try fileSystem.stat(root + "/dst/link").isSymlink))
        #expect(try read(root + "/dst/link") == "content")
    }

    @Test func danglingSymlinkReportsFailureAndContinues() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/src/a.txt")
        try fileSystem.makeSymlink(root + "/src/broken", target: "missing")
        let failures = Failures()
        try copy(makeOperation(TransferOptions(followSymlinks: true), failures: failures), root + "/src", to: root + "/dst")
        #expect(failures.paths == [root + "/src/broken"])
        #expect(try read(root + "/dst/a.txt") == "x")
        #expect(!fileSystem.exists(root + "/dst/broken"))
    }

    @Test func symlinkLoopEndsWithDepthLimitError() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/src/a.txt")
        try fileSystem.makeSymlink(root + "/src/loop", target: ".")
        let failures = Failures()
        try copy(makeOperation(TransferOptions(followSymlinks: true), failures: failures), root + "/src", to: root + "/dst")
        #expect(failures.paths.count == 1)
        #expect(failures.paths[0].hasPrefix(root + "/src/loop"))
        #expect(try read(root + "/dst/a.txt") == "x")
    }

    @Test func statFollowingLinksResolvesTarget() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("12345", to: root + "/file.txt")
        try write("x", to: root + "/dir/x.txt")
        try fileSystem.makeSymlink(root + "/fileLink", target: "file.txt")
        try fileSystem.makeSymlink(root + "/dirLink", target: "dir")
        let file = try fileSystem.statFollowingLinks(root + "/fileLink")
        #expect(!file.isSymlink && !file.isDirectory && file.size == 5)
        #expect(file.name == "fileLink")
        let directory = try fileSystem.statFollowingLinks(root + "/dirLink")
        #expect(directory.isDirectory && !directory.isSymlink)
        #expect(try fileSystem.statFollowingLinks(root + "/file.txt") == fileSystem.stat(root + "/file.txt"))
        #expect(throws: FileError.self) { try fileSystem.statFollowingLinks(root + "/missing") }
    }

    @Test func linkToAncestorIsDetectedWithoutRunaway() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/tree/src/a.txt")
        try write("y", to: root + "/tree/other.txt")
        try fileSystem.makeSymlink(root + "/tree/src/up", target: "..")
        let failures = Failures()
        try copy(makeOperation(TransferOptions(followSymlinks: true), failures: failures), root + "/tree/src", to: root + "/out")
        #expect(failures.paths.count == 1)
        #expect(try read(root + "/out/a.txt") == "x")
        #expect(fileCount(root + "/out") < 20)
    }

    @Test func linkToItselfIsDetectedWithoutRunaway() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/src/a.txt")
        try fileSystem.makeSymlink(root + "/src/self", target: ".")
        let failures = Failures()
        try copy(makeOperation(TransferOptions(followSymlinks: true), failures: failures), root + "/src", to: root + "/out")
        #expect(failures.paths.count == 1)
        #expect(try read(root + "/out/a.txt") == "x")
        #expect(fileCount(root + "/out") < 20)
    }

    @Test func mutuallyReferencingLinksEnd() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("x", to: root + "/tree/a/a.txt")
        try write("y", to: root + "/tree/b/b.txt")
        try fileSystem.makeSymlink(root + "/tree/a/toB", target: "../b")
        try fileSystem.makeSymlink(root + "/tree/b/toA", target: "../a")
        let failures = Failures()
        try copy(makeOperation(TransferOptions(followSymlinks: true), failures: failures), root + "/tree", to: root + "/out")
        #expect(failures.paths.count == 2)
        #expect(try read(root + "/out/a/a.txt") == "x")
        #expect(try read(root + "/out/b/b.txt") == "y")
        #expect(fileCount(root + "/out") < 30)
    }
}
