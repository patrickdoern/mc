import Foundation
import Testing
@testable import MCCore

@Suite struct SMBTargetTests {
    @Test func recognizesSMBAddresses() {
        #expect(SMBTarget.isSMB("smb://host/share"))
        #expect(SMBTarget.isSMB("  SMB://Host/Share"))
        #expect(!SMBTarget.isSMB("ftp://host"))
        #expect(!SMBTarget.isSMB("host/share"))
    }

    @Test func parsesHostAndShare() throws {
        #expect(try SMBTarget.parse("smb://server/daten") == SMBTarget(host: "server", share: "daten"))
        #expect(try SMBTarget.parse("SMB://Server/Daten/") == SMBTarget(host: "Server", share: "Daten"))
    }

    @Test func parsesUserDomainPortAndPath() throws {
        let target = try SMBTarget.parse("smb://FIRMA;anna@nas.local:1445/team/Projekte/2026")
        #expect(target == SMBTarget(host: "nas.local", port: 1445, user: "anna", domain: "FIRMA", share: "team", path: "/Projekte/2026"))
    }

    @Test func parsesAdministrativeShare() throws {
        let target = try SMBTarget.parse("smb://anna@192.0.2.10/c$/mc-test")
        #expect(target == SMBTarget(host: "192.0.2.10", user: "anna", share: "c$", path: "/mc-test"))
    }

    @Test func decodesPercentEncoding() throws {
        let target = try SMBTarget.parse("smb://j%C3%BCrgen@server/Gemeinsame%20Dateien/A%20B")
        #expect(target.user == "jürgen")
        #expect(target.share == "Gemeinsame Dateien")
        #expect(target.path == "/A B")
    }

    @Test func rejectsMissingShareOrHost() {
        #expect(throws: SMBAddressError.invalid("smb://server")) { try SMBTarget.parse("smb://server") }
        #expect(throws: SMBAddressError.invalid("smb://server/")) { try SMBTarget.parse("smb://server/") }
        #expect(throws: SMBAddressError.invalid("smb:///share")) { try SMBTarget.parse("smb:///share") }
        #expect(throws: SMBAddressError.invalid("smb://user@/share")) { try SMBTarget.parse("smb://user@/share") }
        #expect(throws: SMBAddressError.invalid("smb://@server/share")) { try SMBTarget.parse("smb://@server/share") }
        #expect(throws: SMBAddressError.invalid("smb://server/a%zz")) { try SMBTarget.parse("smb://server/a%zz") }
        #expect(throws: SMBAddressError.invalid("ftp://server/share")) { try SMBTarget.parse("ftp://server/share") }
    }

    @Test func rejectsPasswordInAddress() {
        #expect(throws: SMBAddressError.passwordInAddress) { try SMBTarget.parse("smb://anna:geheim@server/share") }
        #expect(throws: SMBAddressError.passwordInAddress) { try SMBTarget.parse("smb://FIRMA;anna:geheim@server:1445/share/x") }
    }

    @Test func buildsDisplayName() throws {
        #expect(try SMBTarget.parse("smb://server/share/a/b").displayName == "smb://server/share")
        #expect(try SMBTarget.parse("smb://FIRMA;anna@server:445/share").displayName == "smb://anna@server/share")
        #expect(try SMBTarget.parse("smb://anna@server:1445/share").displayName == "smb://anna@server:1445/share")
    }

    @Test func buildsMountURLWithoutPathOrPassword() throws {
        #expect(try SMBTarget.parse("smb://server/c$/sub").mountURL?.absoluteString == "smb://server/c$")
        #expect(try SMBTarget.parse("smb://FIRMA;anna@server:1445/team/x").mountURL?.absoluteString == "smb://FIRMA;anna@server:1445/team")
        #expect(try SMBTarget.parse("smb://server/Gemeinsame%20Dateien").mountURL?.absoluteString == "smb://server/Gemeinsame%20Dateien")
    }
}
