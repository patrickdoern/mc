import Foundation
import Testing
@testable import MCCore

@Suite struct FileEntryTests {
    private let modified = Date(timeIntervalSince1970: 1_000)
    private let accessed = Date(timeIntervalSince1970: 2_000)
    private let changed = Date(timeIntervalSince1970: 3_000)
    private let created = Date(timeIntervalSince1970: 4_000)

    @Test func returnsMatchingTimeForEachKind() {
        let entry = FileEntry(name: "a", isDirectory: false, modified: modified, accessed: accessed, changed: changed, created: created)
        #expect(entry.time(.modified) == modified)
        #expect(entry.time(.accessed) == accessed)
        #expect(entry.time(.changed) == changed)
        #expect(entry.time(.created) == created)
    }

    @Test func fallsBackToModified() {
        let entry = FileEntry(name: "a", isDirectory: false, modified: modified)
        #expect(entry.time(.modified) == modified)
        #expect(entry.time(.accessed) == modified)
        #expect(entry.time(.changed) == modified)
        #expect(entry.time(.created) == modified)
    }

    @Test func returnsNilWithoutAnyTime() {
        let entry = FileEntry(name: "a", isDirectory: false)
        #expect(entry.time(.modified) == nil)
        #expect(entry.time(.accessed) == nil)
        #expect(entry.time(.changed) == nil)
        #expect(entry.time(.created) == nil)
    }

    @Test func localFileSystemProvidesAllTimes() throws {
        let root = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let path = root + "/a.txt"
        try "a".write(toFile: path, atomically: true, encoding: .utf8)
        let expected = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: expected], ofItemAtPath: path)
        for entry in [try LocalFileSystem.shared.stat(path), try #require(LocalFileSystem.shared.list(root).first)] {
            #expect(entry.modified == expected)
            #expect(entry.accessed != nil)
            #expect(entry.changed != nil)
            #expect(entry.created != nil)
        }
    }
}
