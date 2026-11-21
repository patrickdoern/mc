import Foundation
import Testing
@testable import MCCore

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

private func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

private func operation(failure: FailureChoice = .skip) -> FileOperation {
    FileOperation(handlers: OperationHandlers(progress: { _ in }, resolveConflict: { _ in .overwrite }, resolveFailure: { _, _ in failure }))
}

private func leftovers(in directory: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.contains(".mc-") }
}

private final class OtherVolume: FileSystem {
    let identity = "local"
    var homePath: String { local.homePath }
    func list(_ path: String) throws -> [FileEntry] { try local.list(path) }
    func stat(_ path: String) throws -> FileEntry { try local.stat(path) }
    func makeDirectory(_ path: String) throws { try local.makeDirectory(path) }
    func removeFile(_ path: String) throws { try local.removeFile(path) }
    func removeDirectory(_ path: String) throws { try local.removeDirectory(path) }
    func readLink(_ path: String) throws -> String { try local.readLink(path) }
    func makeSymlink(_ path: String, target: String) throws { try local.makeSymlink(path, target: target) }
    func setModified(_ path: String, _ date: Date) throws { try local.setModified(path, date) }
    func setPermissions(_ path: String, _ mode: UInt16) throws { try local.setPermissions(path, mode) }
    func openReader(_ path: String) throws -> FileReader { try local.openReader(path) }
    func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter { try local.openWriter(path, permissions: permissions) }

    func rename(_ from: String, _ to: String) throws {
        guard PosixPath.name(from).contains(".mc-") else { throw FileError(path: from, errno: EXDEV) }
        try local.rename(from, to)
    }
}

@Suite struct SafetyRegressionTests {
    @Test func moveToOtherVolumeKeepsSkippedFileInSource() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/src/a.txt")
        try write("b", to: root + "/src/b.txt")
        chmod(root + "/src/b.txt", 0)
        defer { chmod(root + "/src/b.txt", 0o644) }
        let volume = OtherVolume()
        try operation().move([Transfer(source: root + "/src", destination: root + "/dst")], from: volume, to: volume)
        #expect(try read(root + "/dst/a.txt") == "a")
        #expect(FileManager.default.fileExists(atPath: root + "/src/b.txt"))
    }

    @Test func moveOverExistingFileOnOtherVolumeReplacesIt() throws {
        let root = try makeSandbox()
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/dst/a.txt")
        let volume = OtherVolume()
        try operation(failure: .abort).move([Transfer(source: root + "/a.txt", destination: root + "/dst/a.txt")], from: volume, to: volume)
        #expect(try read(root + "/dst/a.txt") == "new")
        #expect(!FileManager.default.fileExists(atPath: root + "/a.txt"))
    }

    @Test func failedOverwriteKeepsExistingFile() throws {
        let root = try makeSandbox()
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/dst/a.txt")
        chmod(root + "/a.txt", 0)
        defer { chmod(root + "/a.txt", 0o644) }
        try operation().copy([Transfer(source: root + "/a.txt", destination: root + "/dst/a.txt")], from: local, to: local)
        #expect(try read(root + "/dst/a.txt") == "old")
        #expect(try leftovers(in: root + "/dst").isEmpty)
    }

    @Test func overwriteLeavesNoTemporaryFile() throws {
        let root = try makeSandbox()
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/dst/a.txt")
        try operation(failure: .abort).copy([Transfer(source: root + "/a.txt", destination: root + "/dst/a.txt")], from: local, to: local)
        #expect(try read(root + "/dst/a.txt") == "new")
        #expect(try leftovers(in: root + "/dst").isEmpty)
    }

    @Test func safeWriteKeepsSymlinkAndExtendedAttributes() throws {
        let root = try makeSandbox()
        try write("old", to: root + "/target.txt")
        try local.makeSymlink(root + "/link.txt", target: "target.txt")
        setxattr(root + "/target.txt", "digital.doern.test", "x", 1, 0, 0)
        try local.writeAllSafely(Data("new".utf8), to: root + "/link.txt", permissions: 0o644)
        #expect(try local.readLink(root + "/link.txt") == "target.txt")
        #expect(try read(root + "/target.txt") == "new")
        #expect(getxattr(root + "/target.txt", "digital.doern.test", nil, 0, 0, 0) == 1)
        #expect(try leftovers(in: root).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func encryptedArchiveMemberFailsInsteadOfHanging() throws {
        let root = try makeSandbox()
        try write("geheim", to: root + "/x.txt")
        _ = try ProcessRunner.run("/usr/bin/zip", ["-q", "-P", "pw", "e.zip", "x.txt"], directory: root)
        let archive = try ArchiveFileSystem(path: root + "/e.zip")
        #expect(throws: FileError.self) { try archive.readAll("/x.txt") }
    }

    @Test(.timeLimit(.minutes(1))) func encryptedArchiveCannotBeRewritten() throws {
        let root = try makeSandbox()
        try write("geheim", to: root + "/x.txt")
        _ = try ProcessRunner.run("/usr/bin/zip", ["-q", "-P", "pw", "e.zip", "x.txt"], directory: root)
        let before = try Data(contentsOf: URL(fileURLWithPath: root + "/e.zip"))
        let archive = try ArchiveFileSystem(path: root + "/e.zip")
        #expect(throws: FileError.self) { try archive.rename("/x.txt", "/y.txt") }
        #expect(try Data(contentsOf: URL(fileURLWithPath: root + "/e.zip")) == before)
    }

    @Test func renamingInArchiveKeepsSymlinkTargets() throws {
        let root = try makeSandbox()
        try write("a", to: root + "/source/dir/a.txt")
        try local.makeSymlink(root + "/source/link", target: "dir/a.txt")
        _ = try ProcessRunner.run("/usr/bin/bsdtar", ["--format", "zip", "-cf", root + "/t.zip", "-C", root + "/source", "."])
        let archive = try ArchiveFileSystem(path: root + "/t.zip")
        try archive.rename("/dir", "/moved")
        #expect(try ArchiveFileSystem(path: root + "/t.zip").readLink("/link") == "dir/a.txt")
    }

    @Test func processRunnerDrainsLargeOutputOnBothStreams() throws {
        let result = try ProcessRunner.run("/bin/sh", ["-c", "head -c 300000 /dev/zero; head -c 300000 /dev/zero >&2; exit 3"])
        #expect(result.status == 3)
        #expect(result.output.count == 300_000)
        #expect(result.errors.count == 300_000)
    }

    @Test func processRunnerMergesErrorsWhenAsked() throws {
        let result = try ProcessRunner.run("/bin/sh", ["-c", "echo out; echo err >&2"], mergingErrors: true)
        #expect(result.outputText.contains("out") && result.outputText.contains("err"))
    }
}
