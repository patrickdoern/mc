import XCTest
@testable import MCCore

private final class NoInteraction: SSHInteraction {
    func trustUnknownHost(_ host: String, keyType: String, fingerprint: String) -> Bool { false }
    func allowUnencryptedLogin(_ host: String) -> Bool { false }
    func trustCertificate(_ host: String, certificate: FTPCertificate, changed: Bool) -> Bool { false }
    func requestSecret(_ prompt: String) -> String? { nil }
    func requestPassword(_ prompt: String, account: String) -> PasswordEntry? { nil }
    func storedPassword(for account: String) -> String? { nil }
    func savePassword(_ password: String, for account: String) {}
    func deletePassword(for account: String) {}
}

final class FTPTargetTests: XCTestCase {
    func testParsesFTPAddresses() {
        XCTAssertEqual(FTPTarget.parse("ftp://host"), FTPTarget(secure: false, host: "host", port: 21, user: "anonymous", path: nil))
        XCTAssertEqual(FTPTarget.parse("ftps://me@host:2121/pub/x"), FTPTarget(secure: true, host: "host", port: 2121, user: "me", path: "/pub/x"))
        XCTAssertEqual(FTPTarget.parse("ftp://me:geheim@host/")?.user, "me")
        XCTAssertNil(FTPTarget.parse("user@host"))
        XCTAssertTrue(FTPTarget.isFTP("FTP://x"))
    }

    func testParsesUnixListing() {
        let listing = """
        drwxr-xr-x   2 ftp ftp      4096 Nov 17 10:00 sub dir
        -rw-r--r--   1 ftp ftp       123 Jan  3  2020 a.txt
        lrwxrwxrwx   1 ftp ftp         5 Nov 17 10:00 link -> a.txt
        """
        let entries = FTPFileSystem.parseList(Data(listing.utf8))
        XCTAssertEqual(entries.map(\.name), ["sub dir", "a.txt", "link"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false, false])
        XCTAssertEqual(entries[1].size, 123)
        XCTAssertEqual(entries[1].permissions, 0o644)
        XCTAssertTrue(entries[2].isSymlink)
    }

    func testParsesMLSD() throws {
        let data = Data("type=cdir;modify=20260101000000; .\ntype=dir;modify=20260101120000; sub\ntype=file;size=12;modify=20260101120000; a b.txt\n".utf8)
        let entries = try XCTUnwrap(FTPFileSystem.parseMLSD(data))
        XCTAssertEqual(entries.map(\.name), ["sub", "a b.txt"])
        XCTAssertEqual(entries[1].size, 12)
        XCTAssertTrue(entries[0].isDirectory)
    }
}

/// Läuft nur mit `MC_TEST_FTP_PORT` (anonymer, schreibbarer Testserver auf 127.0.0.1).
final class FTPFileSystemTests: XCTestCase {
    func testRoundTripAgainstLocalServer() throws {
        guard let port = ProcessInfo.processInfo.environment["MC_TEST_FTP_PORT"].flatMap(Int.init) else { throw XCTSkip("MC_TEST_FTP_PORT nicht gesetzt") }
        let system = try FTPFileSystem(target: FTPTarget(secure: false, host: "127.0.0.1", port: port, user: "anonymous", path: nil), interaction: NoInteraction())
        let name = "mc-test-\(UUID().uuidString)"
        let directory = "/" + name
        try system.makeDirectory(directory)
        XCTAssertTrue(try system.stat(directory).isDirectory)
        try system.writeAll(Data("Hallo FTP".utf8), to: directory + "/Datei mit Leerzeichen.txt", permissions: 0o644)
        XCTAssertEqual(try system.readAll(directory + "/Datei mit Leerzeichen.txt"), Data("Hallo FTP".utf8))
        XCTAssertEqual(try system.list(directory).map(\.name), ["Datei mit Leerzeichen.txt"])
        try system.rename(directory + "/Datei mit Leerzeichen.txt", directory + "/neu.txt")
        XCTAssertEqual(try system.stat(directory + "/neu.txt").size, 9)
        try system.removeFile(directory + "/neu.txt")
        try system.removeDirectory(directory)
        XCTAssertFalse(system.exists(directory))
    }
}
