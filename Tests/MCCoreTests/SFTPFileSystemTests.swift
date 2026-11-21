import Foundation
import Testing
@testable import MCCore

private final class TrustingInteraction: SSHInteraction {
    var trustPrompts = 0

    func trustUnknownHost(_ host: String, keyType: String, fingerprint: String) -> Bool {
        trustPrompts += 1
        return true
    }

    func allowUnencryptedLogin(_ host: String) -> Bool { false }
    func trustCertificate(_ host: String, certificate: FTPCertificate, changed: Bool) -> Bool { false }
    func requestSecret(_ prompt: String) -> String? { nil }
    func requestPassword(_ prompt: String, account: String) -> PasswordEntry? { nil }
    func storedPassword(for account: String) -> String? { nil }
    func savePassword(_ password: String, for account: String) {}
    func deletePassword(for account: String) {}
}

private let fixtureDirectory = ProcessInfo.processInfo.environment["MC_TEST_SSH_DIR"]

@Suite(.enabled(if: fixtureDirectory != nil)) struct SFTPFileSystemTests {
    private func connect(interaction: TrustingInteraction, knownHosts: String) throws -> SFTPFileSystem {
        let settings = SSHSettings(
            hostName: "127.0.0.1",
            user: NSUserName(),
            port: 2222,
            identityFiles: [fixtureDirectory! + "/clientkey"],
            identityAgent: nil,
            knownHostsFile: knownHosts
        )
        return try SFTPFileSystem(settings: settings, interaction: interaction)
    }

    @Test func transfersFilesBothWaysAndRemembersHostKey() throws {
        let root = NSTemporaryDirectory() + "nc-sftp-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root + "/local/tree/sub", withIntermediateDirectories: true)
        try "hello".write(toFile: root + "/local/tree/sub/a.txt", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: root + "/remote", withIntermediateDirectories: true)
        let knownHosts = root + "/known_hosts"
        let interaction = TrustingInteraction()
        let remote = try connect(interaction: interaction, knownHosts: knownHosts)
        #expect(interaction.trustPrompts == 1)
        #expect(try String(contentsOfFile: knownHosts, encoding: .utf8).contains("[127.0.0.1]:2222"))
        _ = try connect(interaction: interaction, knownHosts: knownHosts)
        #expect(interaction.trustPrompts == 1)

        let local = LocalFileSystem.shared
        let handlers = OperationHandlers(progress: { _ in }, resolveConflict: { _ in .overwrite }, resolveFailure: { _, error in Issue.record(error); return .abort })
        try FileOperation(handlers: handlers).copy([Transfer(source: root + "/local/tree", destination: root + "/remote/tree")], from: local, to: remote)
        #expect(try remote.list(root + "/remote/tree").map(\.name).sorted() == ["sub"])
        #expect(try remote.stat(root + "/remote/tree/sub").isDirectory)
        #expect(try String(decoding: remote.readAll(root + "/remote/tree/sub/a.txt"), as: UTF8.self) == "hello")

        try FileOperation(handlers: handlers).copy([Transfer(source: root + "/remote/tree", destination: root + "/back")], from: remote, to: local)
        #expect(try String(contentsOfFile: root + "/back/sub/a.txt", encoding: .utf8) == "hello")

        try FileOperation(handlers: handlers).move([Transfer(source: root + "/remote/tree/sub/a.txt", destination: root + "/remote/moved.txt")], from: remote, to: remote)
        #expect(remote.exists(root + "/remote/moved.txt"))
        #expect(!remote.exists(root + "/remote/tree/sub/a.txt"))

        try local.makeSymlink(root + "/remote/link", target: "moved.txt")
        #expect(try remote.readLink(root + "/remote/link") == "moved.txt")
        #expect(try remote.stat(root + "/remote/link").isSymlink)
        #expect(throws: FileError.self) { try remote.makeSymlink(root + "/remote/other", target: "moved.txt") }

        try FileOperation(handlers: handlers).delete([root + "/remote/tree", root + "/remote/link"], on: remote, trash: false)
        #expect(!remote.exists(root + "/remote/tree"))
        #expect(!remote.exists(root + "/remote/link"))
        #expect(remote.homePath.hasPrefix("/"))
    }

    @Test func reportsMissingPath() throws {
        let remote = try connect(interaction: TrustingInteraction(), knownHosts: NSTemporaryDirectory() + "kh-" + UUID().uuidString)
        #expect(throws: FileError.self) { try remote.list("/definitely/not/here") }
    }
}
