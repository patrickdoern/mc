import Foundation
import Testing
@testable import MCCore

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ data: Data, to path: String) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
}

private func write(_ text: String, to path: String) throws {
    try write(Data(text.utf8), to: path)
}

private func search(_ root: String, _ name: String, content: String? = nil, caseSensitive: Bool = false, useRegex: Bool = false, isCancelled: () -> Bool = { false }) -> [String] {
    var found: [String] = []
    let criteria = SearchCriteria(namePattern: name, content: content, caseSensitive: caseSensitive, useRegex: useRegex)
    FileSearch.run(on: LocalFileSystem.shared, root: root, criteria: criteria, isCancelled: isCancelled) { found.append(PosixPath.name($0)) }
    return found.sorted()
}

@Suite struct FileSearchTests {
    @Test func maskIgnoresCaseByDefault() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("", to: root + "/a.txt")
        try write("", to: root + "/b.TXT")
        try write("", to: root + "/c.md")
        #expect(search(root, "*.TXT") == ["a.txt", "b.TXT"])
        #expect(search(root, "*.TXT", caseSensitive: true) == ["b.TXT"])
    }

    @Test func emptyNameMatchesEverything() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("", to: root + "/a.txt")
        try write("", to: root + "/sub/b.md")
        #expect(search(root, "") == ["a.txt", "b.md", "sub"])
        #expect(search(root, "", useRegex: true) == ["a.txt", "b.md", "sub"])
    }

    @Test func regexOnNameIsUnanchored() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("", to: root + "/foto_12.jpg")
        try write("", to: root + "/FOTO_7.JPG")
        try write("", to: root + "/mein_foto_x.jpg")
        #expect(search(root, #"foto_\d+"#, useRegex: true) == ["FOTO_7.JPG", "foto_12.jpg"])
        #expect(search(root, #"foto_\d+"#, caseSensitive: true, useRegex: true) == ["foto_12.jpg"])
        #expect(search(root, #"^foto_\d+\.jpg$"#, caseSensitive: true, useRegex: true) == ["foto_12.jpg"])
    }

    @Test func plainContentSearch() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("Hallo Welt", to: root + "/a.txt")
        try write("HALLO", to: root + "/b.txt")
        try write("nichts", to: root + "/c.txt")
        #expect(search(root, "*", content: "hallo") == ["a.txt", "b.txt"])
        #expect(search(root, "*", content: "Hallo", caseSensitive: true) == ["a.txt"])
    }

    @Test func plainContentSearchWithUmlauts() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("Äpfel und Birnen", to: root + "/a.txt")
        try write("äpfel", to: root + "/b.txt")
        #expect(search(root, "*", content: "Äpfel") == ["a.txt", "b.txt"])
        #expect(search(root, "*", content: "äpfel") == ["a.txt", "b.txt"])
        #expect(search(root, "*", content: "Äpfel", caseSensitive: true) == ["a.txt"])
    }

    @Test func regexContentMatchesPerLine() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("eins\nTODO später\nzwei", to: root + "/a.txt")
        try write("nicht TODO hier", to: root + "/b.txt")
        try write("fertig\nund aus", to: root + "/c.txt")
        try write("todo\nende", to: root + "/d.txt")
        #expect(search(root, "", content: "^TODO", useRegex: true) == ["a.txt", "d.txt"])
        #expect(search(root, "", content: "^TODO", caseSensitive: true, useRegex: true) == ["a.txt"])
        #expect(search(root, "", content: "^todo$", useRegex: true) == ["d.txt"])
        #expect(search(root, "", content: "^todo$", caseSensitive: true, useRegex: true) == ["d.txt"])
        #expect(search(root, "", content: "^TODO$", caseSensitive: true, useRegex: true) == [])
        #expect(search(root, "", content: "^und aus$", useRegex: true) == ["c.txt"])
    }

    @Test func binaryFilesAndSymlinksAreHandled() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(Data([0x00, 0xFF, 0xFE, 0x41, 0x42, 0x00, 0xC3]), to: root + "/bin.dat")
        try write("AB", to: root + "/real.txt")
        try FileManager.default.createSymbolicLink(atPath: root + "/link.txt", withDestinationPath: root + "/real.txt")
        #expect(search(root, "*", content: "ab") == ["bin.dat", "real.txt"])
        #expect(search(root, "*.dat", content: "AB", caseSensitive: true) == ["bin.dat"])
        #expect(search(root, #"\.dat$"#, content: "AB", useRegex: true) == ["bin.dat"])
        #expect(search(root, "", content: "zzz", useRegex: true) == [])
    }

    @Test func cancellationStopsSearch() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for name in ["a", "b", "c", "d"] { try write("", to: root + "/\(name).txt") }
        var hits = 0
        var cancelled = false
        let criteria = SearchCriteria(namePattern: "*", content: nil)
        FileSearch.run(on: LocalFileSystem.shared, root: root, criteria: criteria, isCancelled: { cancelled }) { _ in
            hits += 1
            cancelled = true
        }
        #expect(hits == 1)
    }

    @Test func validateChecksRegexOnly() throws {
        #expect(throws: Never.self) { try SearchCriteria(namePattern: #"^a\d+$"#, content: "TODO|FIXME", useRegex: true).validate() }
        #expect(throws: Never.self) { try SearchCriteria(namePattern: "", content: nil, useRegex: true).validate() }
        #expect(throws: Never.self) { try SearchCriteria(namePattern: "([", content: "([").validate() }
        do {
            try SearchCriteria(namePattern: "ok", content: "([", useRegex: true).validate()
            Issue.record("validate() hat nicht geworfen")
        } catch {
            #expect(error.localizedDescription.contains("(["))
        }
        #expect(throws: FileError.self) { try SearchCriteria(namePattern: "(", content: nil, useRegex: true).validate() }
    }

    @Test func invalidRegexFindsNothing() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("([", to: root + "/a.txt")
        #expect(search(root, "([", useRegex: true) == [])
        #expect(search(root, "", content: "([", useRegex: true) == [])
        #expect(search(root, "*", content: "([") == ["a.txt"])
    }
}
