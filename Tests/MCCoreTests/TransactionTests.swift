import Foundation
import Testing
@testable import MCCore

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ text: String, to path: String) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private final class CallLog {
    var calls: [String] = []
}

private struct CommitFailure: Error {}

private final class TransactionRecorder: FileSystem {
    let identity: String
    let log: CallLog
    var failsOnCommit = false
    var hasPendingChanges = false
    private let base = LocalFileSystem.shared

    init(_ identity: String, log: CallLog) {
        self.identity = identity
        self.log = log
    }

    var displayName: String { "/archives/" + identity }
    var homePath: String { base.homePath }

    func beginTransaction() { log.calls.append("begin " + identity) }

    func commitTransaction() throws {
        log.calls.append("commit " + identity)
        if failsOnCommit { throw CommitFailure() }
    }

    func rollbackTransaction() { log.calls.append("rollback " + identity) }

    func list(_ path: String) throws -> [FileEntry] { try base.list(path) }
    func stat(_ path: String) throws -> FileEntry { try base.stat(path) }
    func makeDirectory(_ path: String) throws { try base.makeDirectory(path) }
    func removeFile(_ path: String) throws { try base.removeFile(path) }
    func removeDirectory(_ path: String) throws { try base.removeDirectory(path) }
    func rename(_ from: String, _ to: String) throws { try base.rename(from, to) }
    func readLink(_ path: String) throws -> String { try base.readLink(path) }
    func makeSymlink(_ path: String, target: String) throws { try base.makeSymlink(path, target: target) }
    func setModified(_ path: String, _ date: Date) throws { try base.setModified(path, date) }
    func setPermissions(_ path: String, _ mode: UInt16) throws { try base.setPermissions(path, mode) }
    func openReader(_ path: String) throws -> FileReader { try base.openReader(path) }
    func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter { try base.openWriter(path, permissions: permissions) }
}

@Suite struct TransactionTests {
    private let log = CallLog()

    private func recorder(_ name: String) -> TransactionRecorder {
        TransactionRecorder(name, log: log)
    }

    private func operation(
        progress: @escaping (OperationProgress) -> Void = { _ in },
        conflict: ConflictChoice = .overwrite,
        failure: FailureChoice = .abort
    ) -> FileOperation {
        FileOperation(handlers: OperationHandlers(
            progress: progress,
            resolveConflict: { _ in conflict },
            resolveFailure: { _, _ in failure }
        ))
    }

    @Test func copyBetweenSystemsBeginsAndCommitsBoth() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try operation().copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        #expect(log.calls == ["begin src", "begin dst", "commit dst", "commit src"])
        #expect(FileManager.default.fileExists(atPath: root + "/b.txt"))
    }

    @Test func sameObjectIsTransactedOnce() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        let system = recorder("one")
        try operation().copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: system, to: system)
        #expect(log.calls == ["begin one", "commit one"])
    }

    @Test func sameIdentityIsTransactedOnce() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try operation().copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("one"), to: recorder("one"))
        #expect(log.calls == ["begin one", "commit one"])
    }

    @Test func moveBetweenSystemsCommitsBoth() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try operation().move([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        #expect(log.calls == ["begin src", "begin dst", "commit dst", "commit src"])
        #expect(!FileManager.default.fileExists(atPath: root + "/a.txt"))
    }

    @Test func moveWithinSystemCommitsOnce() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        let system = recorder("one")
        try operation().move([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: system, to: system)
        #expect(log.calls == ["begin one", "commit one"])
    }

    @Test func deleteCommits() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try operation().delete([root + "/a.txt"], on: recorder("one"), trash: false)
        #expect(log.calls == ["begin one", "commit one"])
        #expect(!FileManager.default.fileExists(atPath: root + "/a.txt"))
    }

    @Test func abortByFailureRollsBackBoth() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(throws: OperationAborted.self) {
            try operation().copy([Transfer(source: root + "/missing.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        }
        #expect(log.calls == ["begin src", "begin dst", "rollback src", "rollback dst"])
    }

    @Test func cancelRollsBackBoth() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        let operation = operation()
        operation.cancel()
        #expect(throws: OperationAborted.self) {
            try operation.delete([root + "/a.txt"], on: recorder("one"), trash: false)
        }
        #expect(log.calls == ["begin one", "rollback one"])
        #expect(FileManager.default.fileExists(atPath: root + "/a.txt"))
    }

    @Test func conflictCancelRollsBack() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try write("b", to: root + "/b.txt")
        #expect(throws: OperationAborted.self) {
            try operation(conflict: .cancel).copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        }
        #expect(log.calls == ["begin src", "begin dst", "rollback src", "rollback dst"])
    }

    @Test func skippedFilesStillCommit() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        try write("b", to: root + "/b.txt")
        try operation(conflict: .skip).copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        #expect(log.calls == ["begin src", "begin dst", "commit dst", "commit src"])
    }

    @Test func skippedFailuresStillCommit() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try operation(failure: .skip).copy([Transfer(source: root + "/missing.txt", destination: root + "/b.txt")], from: recorder("src"), to: recorder("dst"))
        #expect(log.calls == ["begin src", "begin dst", "commit dst", "commit src"])
    }

    @Test func failingCommitRollsBackUncommittedSystems() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        let destination = recorder("dst")
        destination.failsOnCommit = true
        #expect(throws: CommitFailure.self) {
            try operation().copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: recorder("src"), to: destination)
        }
        #expect(log.calls == ["begin src", "begin dst", "commit dst", "rollback dst", "rollback src"])
    }

    @Test func progressShowsSystemNameBeforeCommitOnlyWithPendingChanges() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("a", to: root + "/a.txt")
        let pending = recorder("pending.zip")
        pending.hasPendingChanges = true
        let idle = recorder("idle.zip")
        let observed = CallLog()
        let operation = operation(progress: { observed.calls.append($0.currentPath) })
        try operation.copy([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: idle, to: pending)
        #expect(observed.calls.last == "pending.zip")
        #expect(!observed.calls.contains("idle.zip"))
    }
}
