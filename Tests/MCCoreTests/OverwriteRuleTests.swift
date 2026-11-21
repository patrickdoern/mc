import Foundation
import Testing
@testable import MCCore

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

private func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

private final class Counter {
    var asked = 0
}

private func makeOperation(_ rule: OverwriteRule, counter: Counter = Counter(), answer: ConflictChoice = .overwrite) -> FileOperation {
    FileOperation(
        handlers: OperationHandlers(
            progress: { _ in },
            resolveConflict: { _ in counter.asked += 1; return answer },
            resolveFailure: { _, _ in .abort }
        ),
        options: TransferOptions(overwriteRule: rule)
    )
}

@Suite struct OverwriteRuleTests {
    let fileSystem = LocalFileSystem.shared
    let now = Date()

    private func copy(_ operation: FileOperation, _ root: String, _ name: String = "a.txt", to target: String = "b.txt") throws {
        try operation.copy([Transfer(source: root + "/" + name, destination: root + "/" + target)], from: fileSystem, to: fileSystem)
    }

    @Test func rawValuesFollowSettingOrder() {
        #expect([OverwriteRule.ask, .overwrite, .ifNewer, .ifSizeDiffers, .skip].map(\.rawValue) == [0, 1, 2, 3, 4])
    }

    @Test func defaultOptions() {
        let options = TransferOptions()
        #expect(options.overwriteRule == .ask)
        #expect(options.preserveAttributes)
        #expect(!options.followSymlinks)
    }

    @Test func overwriteRuleReplacesWithoutAsking() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        let counter = Counter()
        try copy(makeOperation(.overwrite, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "new")
        #expect(counter.asked == 0)
    }

    @Test func skipRuleKeepsExistingWithoutAsking() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        let counter = Counter()
        try copy(makeOperation(.skip, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "old")
        #expect(counter.asked == 0)
    }

    @Test func askRuleUsesHandler() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        let counter = Counter()
        try copy(makeOperation(.ask, counter: counter, answer: .skip), root)
        #expect(try read(root + "/b.txt") == "old")
        #expect(counter.asked == 1)
        try copy(makeOperation(.ask, counter: counter, answer: .overwrite), root)
        #expect(try read(root + "/b.txt") == "new")
        #expect(counter.asked == 2)
    }

    @Test func ifNewerReplacesOnlyWhenSourceIsNewer() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let counter = Counter()
        try write("newer", to: root + "/a.txt", modified: now)
        try write("old", to: root + "/b.txt", modified: now - 100)
        try copy(makeOperation(.ifNewer, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "newer")

        try write("older", to: root + "/a.txt", modified: now - 200)
        try write("keep", to: root + "/b.txt", modified: now)
        try copy(makeOperation(.ifNewer, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "keep")

        try write("same", to: root + "/a.txt", modified: now + 1)
        try write("keep", to: root + "/b.txt", modified: now)
        try copy(makeOperation(.ifNewer, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "keep")

        try write("barely", to: root + "/a.txt", modified: now + 3)
        try copy(makeOperation(.ifNewer, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "barely")
        #expect(counter.asked == 0)
    }

    @Test func ifSizeDiffersComparesSizes() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let counter = Counter()
        try write("12345", to: root + "/a.txt")
        try write("abcde", to: root + "/b.txt")
        try copy(makeOperation(.ifSizeDiffers, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "abcde")
        try write("abc", to: root + "/b.txt")
        try copy(makeOperation(.ifSizeDiffers, counter: counter, answer: .cancel), root)
        #expect(try read(root + "/b.txt") == "12345")
        #expect(counter.asked == 0)
    }

    @Test func overwriteThenRuleAppliesToFurtherConflicts() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for name in ["1", "2", "3"] {
            try write("src" + name, to: root + "/src/" + name, modified: now)
        }
        try write("old1", to: root + "/dst/1", modified: now - 100)
        try write("old2", to: root + "/dst/2", modified: now + 100)
        try write("old3", to: root + "/dst/3", modified: now - 100)
        let counter = Counter()
        try makeOperation(.ask, counter: counter, answer: .overwriteThenRule(.ifNewer))
            .copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(counter.asked == 1)
        #expect(try read(root + "/dst/1") == "src1")
        #expect(try read(root + "/dst/2") == "old2")
        #expect(try read(root + "/dst/3") == "src3")
    }

    @Test func skipThenRuleAppliesToFurtherConflicts() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for name in ["1", "2", "3"] {
            try write("src" + name, to: root + "/src/" + name)
            try write("old" + name, to: root + "/dst/" + name)
        }
        try write("longer3", to: root + "/src/3")
        let counter = Counter()
        try makeOperation(.ask, counter: counter, answer: .skipThenRule(.ifSizeDiffers))
            .copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(counter.asked == 1)
        let contents = try ["1", "2", "3"].map { try read(root + "/dst/" + $0) }
        #expect(contents.filter { $0.hasPrefix("old") }.count == 2)
        #expect(contents.contains("longer3"))
    }

    @Test func overwriteAllAndSkipAllKeepTheirMeaning() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for name in ["1", "2", "3"] {
            try write("src" + name, to: root + "/src/" + name)
            try write("old" + name, to: root + "/dst/" + name)
        }
        let counter = Counter()
        try makeOperation(.ask, counter: counter, answer: .skipAll)
            .copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(counter.asked == 1)
        #expect(try read(root + "/dst/1") == "old1")
        #expect(try read(root + "/dst/3") == "old3")
        try makeOperation(.ask, counter: counter, answer: .overwriteAll)
            .copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(counter.asked == 2)
        #expect(try read(root + "/dst/1") == "src1")
        #expect(try read(root + "/dst/3") == "src3")
    }

    @Test func moveWithSkipKeepsSource() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("new", to: root + "/a.txt")
        try write("old", to: root + "/b.txt")
        try makeOperation(.skip).move([Transfer(source: root + "/a.txt", destination: root + "/b.txt")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/a.txt") == "new")
        #expect(try read(root + "/b.txt") == "old")
    }

    @Test func moveWithIfNewerInSubfolders() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("fresh", to: root + "/src/sub/new.txt", modified: now)
        try write("stale", to: root + "/src/sub/old.txt", modified: now - 500)
        try write("was", to: root + "/dst/sub/new.txt", modified: now - 100)
        try write("was", to: root + "/dst/sub/old.txt", modified: now - 100)
        try makeOperation(.ifNewer, answer: .cancel)
            .move([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/dst/sub/new.txt") == "fresh")
        #expect(try read(root + "/dst/sub/old.txt") == "was")
        #expect(!fileSystem.exists(root + "/src/sub/new.txt"))
        #expect(try read(root + "/src/sub/old.txt") == "stale")
    }

    @Test func copyWithSkipInSubfoldersLeavesExistingFiles() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("new", to: root + "/src/sub/a.txt")
        try write("added", to: root + "/src/sub/c.txt")
        try write("old", to: root + "/dst/sub/a.txt")
        try makeOperation(.skip).copy([Transfer(source: root + "/src", destination: root + "/dst")], from: fileSystem, to: fileSystem)
        #expect(try read(root + "/dst/sub/a.txt") == "old")
        #expect(try read(root + "/dst/sub/c.txt") == "added")
    }
}
