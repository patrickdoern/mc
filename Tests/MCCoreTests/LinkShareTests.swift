import Foundation
import Testing
@testable import MCCore

private func makeSandbox() throws -> String {
    let path = NSTemporaryDirectory() + "mc-link-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ data: Data, to path: String) throws {
    try FileManager.default.createDirectory(atPath: PosixPath.parent(path), withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
}

private func ask(_ share: LinkShare, _ message: LinkMessage) -> [LinkMessage] {
    share.answer(LinkFrame(requestID: 42, message: message)).map(\.message)
}

private func entries(_ share: LinkShare, _ path: String) -> [FileEntry]? {
    guard case .entries(let entries, false) = ask(share, .list(path)).first else { return nil }
    return entries
}

private func errorText(_ share: LinkShare, _ message: LinkMessage) -> String? {
    guard case .error(let text) = ask(share, message).first else { return nil }
    return text
}

@Suite struct LinkShareTests {
    let root: String
    let share: LinkShare

    init() throws {
        root = try makeSandbox()
        try write(Data("a".utf8), to: root + "/one/Docs/a.txt")
        try write(Data("b".utf8), to: root + "/one/Docs/sub/b.txt")
        try write(Data("c".utf8), to: root + "/two/Docs/c.txt")
        try write(Data("geheim".utf8), to: root + "/outside/secret.txt")
        try write(Data("nah".utf8), to: root + "/one/Docsbc/near.txt")
        let fileSystem = LocalFileSystem.shared
        try fileSystem.makeSymlink(root + "/one/Docs/out", target: root + "/outside")
        try fileSystem.makeSymlink(root + "/one/Docs/relout", target: "../../outside/secret.txt")
        try fileSystem.makeSymlink(root + "/one/Docs/near", target: "../Docsbc/near.txt")
        try fileSystem.makeSymlink(root + "/one/Docs/inner", target: "sub/b.txt")
        try fileSystem.makeSymlink(root + "/one/Docs/absinner", target: root + "/one/Docs/sub")
        share = LinkShare(folders: [root + "/one/Docs", root + "/two/Docs/"])
    }

    @Test func rootListsSharedFoldersWithUniqueNames() throws {
        let list = try #require(entries(share, "/"))
        #expect(list.map(\.name) == ["Docs", "Docs (2)"])
        #expect(list.allSatisfy { $0.isDirectory })
        #expect(entries(share, "/Docs (2)")?.map(\.name) == ["c.txt"])
        guard case .entry(let entry) = ask(share, .stat("/Docs (2)")).first else { Issue.record("no entry"); return }
        #expect(entry.name == "Docs (2)")
        #expect(ask(share, .stat("/")) == [.entry(FileEntry(name: "", isDirectory: true, permissions: 0o555))])
    }

    @Test func listsFolderWithOutwardLinksAsLinks() throws {
        let list = try #require(entries(share, "/Docs"))
        #expect(Set(list.map(\.name)) == ["a.txt", "sub", "out", "relout", "near", "inner", "absinner"])
        #expect(list.first { $0.name == "out" }?.isSymlink == true)
        guard case .entry(let entry) = ask(share, .stat("/Docs/out")).first else { Issue.record("no entry"); return }
        #expect(entry.isSymlink)
    }

    @Test func normalizesPaths() {
        #expect(entries(share, "/Docs/sub/../sub/./")?.map(\.name) == ["b.txt"])
        #expect(entries(share, "//Docs//sub")?.map(\.name) == ["b.txt"])
    }

    @Test func rejectsParentBeyondRoot() {
        let outside = localized("Außerhalb der Freigabe")
        #expect(errorText(share, .list("/..")) == outside)
        #expect(errorText(share, .list("/Docs/../..")) == outside)
        #expect(errorText(share, .openRead("/Docs/sub/../../../outside/secret.txt")) == outside)
    }

    @Test func rejectsFollowingLinksOutside() {
        let outside = localized("Außerhalb der Freigabe")
        #expect(errorText(share, .list("/Docs/out")) == outside)
        #expect(errorText(share, .statFollowingLinks("/Docs/out")) == outside)
        #expect(errorText(share, .openRead("/Docs/out/secret.txt")) == outside)
        #expect(errorText(share, .stat("/Docs/out/secret.txt")) == outside)
        #expect(errorText(share, .openRead("/Docs/relout")) == outside)
        #expect(errorText(share, .openRead("/Docs/near")) == outside)
        #expect(errorText(share, .readLink("/Docs/out")) == outside)
        #expect(errorText(share, .readLink("/Docs/relout")) == outside)
        #expect(errorText(share, .readLink("/Docs/near")) == outside)
    }

    @Test func followsLinksInside() {
        #expect(ask(share, .readLink("/Docs/inner")) == [.text("sub/b.txt")])
        #expect(ask(share, .readLink("/Docs/absinner")) == [.text("/Docs/sub")])
        guard case .entry(let entry) = ask(share, .statFollowingLinks("/Docs/inner")).first else { Issue.record("no entry"); return }
        #expect(entry.name == "inner")
        #expect(!entry.isSymlink)
        #expect(entry.size == 1)
        #expect(entries(share, "/Docs/absinner")?.map(\.name) == ["b.txt"])
    }

    @Test func errorsNeverContainLocalPaths() {
        let missing = errorText(share, .stat("/Docs/fehlt.txt"))
        #expect(missing == "/Docs/fehlt.txt: " + String(cString: strerror(ENOENT)))
        let notDirectory = errorText(share, .list("/Docs/a.txt"))
        #expect(notDirectory == "/Docs/a.txt: " + String(cString: strerror(ENOTDIR)))
        #expect(errorText(share, .readLink("/Docs (2)")) == "/Docs (2): " + String(cString: strerror(EINVAL)))
        #expect(errorText(share, .list("/Unbekannt")) == "/Unbekannt: " + String(cString: strerror(ENOENT)))
        for text in [missing, notDirectory] { #expect(text?.contains(root) == false) }
    }

    @Test func rejectsEveryOtherRequestAsReadOnly() {
        let readOnly = localized("Die Freigabe ist nur lesbar")
        let requests: [LinkMessage] = [
            .makeDirectory("/Docs/neu"),
            .removeFile("/Docs/a.txt"),
            .removeDirectory("/Docs/sub"),
            .rename("/Docs/a.txt", "/Docs/z.txt"),
            .makeSymlink("/Docs/l", target: "a.txt"),
            .setModified("/Docs/a.txt", Date()),
            .setPermissions("/Docs/a.txt", 0o600),
            .openWrite("/Docs/neu.txt", permissions: 0o644),
            .hello(version: 1, name: "x"),
            .done,
        ]
        for request in requests { #expect(errorText(share, request) == readOnly) }
        #expect(FileManager.default.fileExists(atPath: root + "/one/Docs/a.txt"))
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/neu"))
    }

    @Test func readsFileInBlocks() throws {
        let content = Data((0..<(LinkProtocol.maximumBlock * 2 + 1234)).map { UInt8($0 % 251) })
        try write(content, to: root + "/one/Docs/gross.bin")
        guard case .handle(let handle) = ask(share, .openRead("/Docs/gross.bin")).first else { Issue.record("no handle"); return }
        var received = Data()
        while true {
            guard case .data(let block) = ask(share, .read(handle: handle, length: UInt32(LinkProtocol.maximumPayload))).first else { Issue.record("no data"); return }
            #expect(block.count <= LinkProtocol.maximumBlock)
            if block.isEmpty { break }
            received += block
        }
        #expect(received == content)
        #expect(ask(share, .close(handle: handle)) == [.done])
        #expect(errorText(share, .read(handle: handle, length: 10)) == String(cString: strerror(EBADF)))
    }

    @Test func answersWithRequestID() {
        let frames = share.answer(LinkFrame(requestID: 99, message: .stat("/Docs/a.txt")))
        #expect(frames.map(\.requestID) == [99])
    }

    @Test func pathBoundaryIsRespected() {
        #expect(LinkShare.isInside("/a/b", "/a/b"))
        #expect(LinkShare.isInside("/a/b/c", "/a/b"))
        #expect(!LinkShare.isInside("/a/bc", "/a/b"))
        #expect(LinkShare.isInside("/a", "/"))
    }
}
