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
    let writer: LinkShare

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
        share = LinkShare(folders: [root + "/one/Docs", root + "/two/Docs/"], writable: false)
        writer = LinkShare(folders: [root + "/one/Docs", root + "/two/Docs/"], writable: true)
    }

    private func content(_ path: String) -> Data? {
        FileManager.default.contents(atPath: root + path)
    }

    private func permissions(_ path: String) throws -> UInt16 {
        try LocalFileSystem.shared.stat(root + path).permissions & 0o7777
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
            .write(handle: 1, data: Data("x".utf8)),
            .finish(handle: 1),
            .abort(handle: 1),
            .trash("/Docs/a.txt"),
            .hello(version: 1, name: "x", writable: true, knowsPeer: false),
            .done,
        ]
        for request in requests { #expect(errorText(share, request) == readOnly) }
        #expect(FileManager.default.fileExists(atPath: root + "/one/Docs/a.txt"))
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/neu"))
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/neu.txt"))
    }

    @Test func writesFileInBlocksWithLimitedPermissions() throws {
        let content = Data((0..<(LinkProtocol.maximumBlock * 2 + 77)).map { UInt8($0 % 241) })
        guard case .handle(let handle) = ask(writer, .openWrite("/Docs/neu.bin", permissions: 0o4755)).first else { Issue.record("no handle"); return }
        var offset = 0
        while offset < content.count {
            let block = content[offset..<min(offset + LinkProtocol.maximumBlock, content.count)]
            #expect(ask(writer, .write(handle: handle, data: Data(block))) == [.done])
            offset += block.count
        }
        #expect(ask(writer, .finish(handle: handle)) == [.done])
        #expect(self.content("/one/Docs/neu.bin") == content)
        #expect(try permissions("/one/Docs/neu.bin") & 0o7000 == 0)
        #expect(errorText(writer, .write(handle: handle, data: Data("x".utf8))) == String(cString: strerror(EBADF)))
        #expect(errorText(writer, .finish(handle: handle)) == String(cString: strerror(EBADF)))
        guard case .handle(let reading) = ask(writer, .openRead("/Docs/a.txt")).first else { Issue.record("no handle"); return }
        #expect(errorText(writer, .write(handle: reading, data: Data("x".utf8))) == String(cString: strerror(EBADF)))
    }

    @Test func overwritesFileAndFollowsLinkInside() throws {
        guard case .handle(let handle) = ask(writer, .openWrite("/Docs/inner", permissions: 0o644)).first else { Issue.record("no handle"); return }
        #expect(ask(writer, .write(handle: handle, data: Data("neu".utf8))) == [.done])
        #expect(ask(writer, .finish(handle: handle)) == [.done])
        #expect(content("/one/Docs/sub/b.txt") == Data("neu".utf8))
        #expect(try LocalFileSystem.shared.stat(root + "/one/Docs/inner").isSymlink)
    }

    @Test func abortKeepsPartialFile() {
        guard case .handle(let handle) = ask(writer, .openWrite("/Docs/teil.bin", permissions: 0o644)).first else { Issue.record("no handle"); return }
        #expect(ask(writer, .write(handle: handle, data: Data("teil".utf8))) == [.done])
        #expect(ask(writer, .abort(handle: handle)) == [.done])
        #expect(ask(writer, .abort(handle: handle)) == [.done])
        #expect(errorText(writer, .write(handle: handle, data: Data("x".utf8))) == String(cString: strerror(EBADF)))
        #expect(content("/one/Docs/teil.bin") == Data("teil".utf8))
    }

    @Test func endClosesOpenHandles() {
        guard case .handle(let written) = ask(writer, .openWrite("/Docs/offen.bin", permissions: 0o644)).first,
              case .handle(let read) = ask(writer, .openRead("/Docs/a.txt")).first else { Issue.record("no handle"); return }
        #expect(ask(writer, .write(handle: written, data: Data("halb".utf8))) == [.done])
        writer.end()
        #expect(errorText(writer, .write(handle: written, data: Data("x".utf8))) == String(cString: strerror(EBADF)))
        #expect(errorText(writer, .finish(handle: written)) == String(cString: strerror(EBADF)))
        #expect(errorText(writer, .read(handle: read, length: 10)) == String(cString: strerror(EBADF)))
        #expect(content("/one/Docs/offen.bin") == Data("halb".utf8))
    }

    @Test func createsRenamesAndRemovesEntries() throws {
        #expect(ask(writer, .makeDirectory("/Docs/neu")) == [.done])
        #expect(ask(writer, .rename("/Docs/a.txt", "/Docs/neu/z.txt")) == [.done])
        #expect(content("/one/Docs/neu/z.txt") == Data("a".utf8))
        #expect(ask(writer, .makeSymlink("/Docs/neu/link", target: "../sub/b.txt")) == [.done])
        #expect(ask(writer, .readLink("/Docs/neu/link")) == [.text("../sub/b.txt")])
        #expect(ask(writer, .rename("/Docs/inner", "/Docs/neu/inner")) == [.done])
        #expect(try LocalFileSystem.shared.readLink(root + "/one/Docs/neu/inner") == "sub/b.txt")
        #expect(ask(writer, .removeFile("/Docs/neu/link")) == [.done])
        #expect(ask(writer, .removeFile("/Docs/neu/inner")) == [.done])
        #expect(ask(writer, .removeFile("/Docs/out")) == [.done])
        #expect(ask(writer, .removeFile("/Docs/neu/z.txt")) == [.done])
        #expect(ask(writer, .removeDirectory("/Docs/neu")) == [.done])
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/neu"))
        #expect(content("/one/Docs/sub/b.txt") == Data("b".utf8))
        #expect(content("/outside/secret.txt") == Data("geheim".utf8))
    }

    @Test func setsModifiedAndLimitsPermissions() throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        #expect(ask(writer, .setModified("/Docs/a.txt", date)) == [.done])
        #expect(try LocalFileSystem.shared.stat(root + "/one/Docs/a.txt").modified == date)
        #expect(ask(writer, .setPermissions("/Docs/a.txt", 0o6777)) == [.done])
        #expect(try permissions("/one/Docs/a.txt") == 0o777)
        #expect(ask(writer, .setPermissions("/Docs/inner", 0o1600)) == [.done])
        #expect(try permissions("/one/Docs/sub/b.txt") == 0o600)
    }

    @Test func movesEntriesToTrash() throws {
        let name = "mc-link-trash-" + UUID().uuidString
        try write(Data("weg".utf8), to: root + "/one/Docs/" + name + "/inhalt.txt")
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: root), create: false)
        let trashed = trash.appendingPathComponent(name)
        #expect(ask(writer, .trash("/Docs/" + name)) == [.done])
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/" + name))
        #expect(FileManager.default.contents(atPath: trashed.path + "/inhalt.txt") == Data("weg".utf8))
        try FileManager.default.removeItem(at: trashed)
    }

    @Test func rejectsChangesThroughLinksOutside() throws {
        let outside = localized("Außerhalb der Freigabe")
        let before = try permissions("/outside/secret.txt")
        let modified = try LocalFileSystem.shared.stat(root + "/outside/secret.txt").modified
        let requests: [LinkMessage] = [
            .setPermissions("/Docs/relout", 0o777),
            .setPermissions("/Docs/out", 0o777),
            .setModified("/Docs/relout", Date(timeIntervalSince1970: 0)),
            .setModified("/Docs/out/secret.txt", Date(timeIntervalSince1970: 0)),
            .openWrite("/Docs/relout", permissions: 0o644),
            .openWrite("/Docs/near", permissions: 0o644),
            .openWrite("/Docs/out/secret.txt", permissions: 0o644),
            .openWrite("/Docs/out/neu.txt", permissions: 0o644),
            .makeDirectory("/Docs/out/neu"),
            .removeFile("/Docs/out/secret.txt"),
            .trash("/Docs/out/secret.txt"),
            .rename("/Docs/out/secret.txt", "/Docs/geholt.txt"),
            .rename("/Docs/a.txt", "/Docs/out/a.txt"),
            .makeSymlink("/Docs/out/l", target: "secret.txt"),
            .makeDirectory("/Docs/../../neu"),
        ]
        for request in requests { #expect(errorText(writer, request) == outside) }
        #expect(content("/outside/secret.txt") == Data("geheim".utf8))
        #expect(content("/one/Docsbc/near.txt") == Data("nah".utf8))
        #expect(try permissions("/outside/secret.txt") == before)
        #expect(try LocalFileSystem.shared.stat(root + "/outside/secret.txt").modified == modified)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root + "/outside") == ["secret.txt"])
        #expect(!FileManager.default.fileExists(atPath: root + "/one/neu"))
    }

    @Test func rejectsChangingRootAndSharedFolders() throws {
        let unchangeable = localized("Freigegebene Ordner lassen sich nicht ändern")
        try LocalFileSystem.shared.makeSymlink(root + "/one/Docs/self", target: ".")
        let requests: [LinkMessage] = [
            .removeDirectory("/Docs"),
            .removeDirectory("/"),
            .removeFile("/Docs (2)"),
            .trash("/Docs"),
            .rename("/Docs", "/Andere"),
            .rename("/Docs/a.txt", "/Docs (2)"),
            .rename("/Docs/sub", "/Docs"),
            .setModified("/Docs", Date()),
            .setPermissions("/Docs (2)", 0o777),
            .setPermissions("/Docs/self", 0o777),
            .setPermissions("/", 0o777),
            .makeDirectory("/"),
            .makeDirectory("/Neu"),
            .makeSymlink("/Link", target: "Docs"),
            .openWrite("/neu.txt", permissions: 0o644),
            .openWrite("/Docs", permissions: 0o644),
        ]
        for request in requests { #expect(errorText(writer, request) == unchangeable) }
        #expect(content("/one/Docs/a.txt") == Data("a".utf8))
        #expect(content("/two/Docs/c.txt") == Data("c".utf8))
    }

    @Test func rejectsRenameBetweenShares() {
        #expect(errorText(writer, .rename("/Docs/a.txt", "/Docs (2)/a.txt")) == localized("Außerhalb der Freigabe"))
        #expect(content("/one/Docs/a.txt") == Data("a".utf8))
        #expect(!FileManager.default.fileExists(atPath: root + "/two/Docs/a.txt"))
    }

    @Test func rejectsParentReferenceAsLastPart() {
        #expect(errorText(writer, .removeDirectory("/Docs/sub/x/..")) == "/Docs/sub/x/..: " + String(cString: strerror(EINVAL)))
        #expect(errorText(writer, .makeDirectory("/Docs/sub/.")) == "/Docs/sub/.: " + String(cString: strerror(EINVAL)))
        #expect(errorText(writer, .rename("/Docs/a.txt", "/Docs/sub/..")) == "/Docs/sub/..: " + String(cString: strerror(EINVAL)))
        #expect(FileManager.default.fileExists(atPath: root + "/one/Docs/sub/b.txt"))
    }

    @Test func rejectsSymlinkTargetsLeavingShare() {
        let outside = localized("Außerhalb der Freigabe")
        for target in [root + "/outside/secret.txt", "/etc", "../Docsbc/near.txt", "sub/../../outside", "../../../../../../.."] {
            #expect(errorText(writer, .makeSymlink("/Docs/l", target: target)) == outside)
        }
        #expect(!FileManager.default.fileExists(atPath: root + "/one/Docs/l"))
        #expect(ask(writer, .makeSymlink("/Docs/sub/l", target: "../a.txt")) == [.done])
    }

    @Test func writeErrorsContainOnlyVirtualPaths() throws {
        try LocalFileSystem.shared.setPermissions(root + "/one/Docs/sub", 0o555)
        defer { try? LocalFileSystem.shared.setPermissions(root + "/one/Docs/sub", 0o755) }
        let errors = [
            errorText(writer, .openWrite("/Docs/sub/neu.txt", permissions: 0o644)),
            errorText(writer, .makeDirectory("/Docs/sub/neu")),
            errorText(writer, .removeFile("/Docs/sub/b.txt")),
            errorText(writer, .removeFile("/Docs/fehlt.txt")),
            errorText(writer, .removeDirectory("/Docs/sub")),
            errorText(writer, .rename("/Docs/fehlt.txt", "/Docs/z.txt")),
            errorText(writer, .openWrite("/Docs/fehlt/neu.txt", permissions: 0o644)),
            errorText(writer, .setModified("/Docs/fehlt.txt", Date())),
            errorText(writer, .trash("/Docs/fehlt.txt")),
        ]
        #expect(errors[0] == "/Docs/sub/neu.txt: " + String(cString: strerror(EACCES)))
        #expect(errors[1] == "/Docs/sub/neu: " + String(cString: strerror(EACCES)))
        #expect(errors[2] == "/Docs/sub/b.txt: " + String(cString: strerror(EACCES)))
        #expect(errors[3] == "/Docs/fehlt.txt: " + String(cString: strerror(ENOENT)))
        #expect(errors[4] == "/Docs/sub: " + String(cString: strerror(ENOTEMPTY)))
        #expect(errors[5] == "/Docs/fehlt.txt: " + String(cString: strerror(ENOENT)))
        #expect(errors[6] == "/Docs/fehlt: " + String(cString: strerror(ENOENT)))
        #expect(errors[7] == "/Docs/fehlt.txt: " + String(cString: strerror(ENOENT)))
        for text in errors {
            #expect(text != nil)
            #expect(text?.contains(root) == false)
            #expect(text?.contains("/private/") == false)
        }
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
