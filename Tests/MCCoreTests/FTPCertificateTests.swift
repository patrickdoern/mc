import Foundation
import Testing
@testable import MCCore

private let pem = """
-----BEGIN CERTIFICATE-----
MIIBVzCB/qADAgECAhQF3LRmYgThg5/SOXgKnS0yhDUlRDAKBggqhkjOPQQDAjAS
MRAwDgYDVQQDDAdtYyB0ZXN0MB4XDTI2MTEyMTE3NTIzNFoXDTM2MTExODE3NTIz
NFowEjEQMA4GA1UEAwwHbWMgdGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IA
BNtwu8zchNUs+XCybncCutF7/KdQeYFYGeOWPHaULFw7N+kt//tlw3wa2NQHq80U
bTrruPsuzVmQgOALIhpKRmijMjAwMB0GA1UdDgQWBBSUbhNzz/bIjlbM+OrQ+kmC
NGU+pTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIQDIVy7ZBdtB
2l0X4iR0xS2e5bB97L1bwYEo6EzOpyDxnAIgZsodBWNnfjcf5fLT/qD2LHSSR75J
bD7w/dhK7ub+sJg=
-----END CERTIFICATE-----
"""

@Suite struct FTPCertificateTests {
    @Test func readsCertificateInfoFromCurlEntries() throws {
        let certificate = try #require(FTPCertificate(entries: ["Subject:CN = mc test", "Issuer:CN = mc test", "Expire date:Nov 18 17:52:34 2036 GMT", "Cert:" + pem]))
        #expect(certificate.subject == "CN = mc test")
        #expect(certificate.issuer == "CN = mc test")
        #expect(certificate.expires == "Nov 18 17:52:34 2036 GMT")
        #expect(certificate.fingerprint == "9A:E5:FD:4D:49:19:44:EC:1F:96:6E:4E:8F:7A:28:BA:FB:10:9F:7C:09:1D:DE:9F:65:9C:61:5C:11:CE:51:14")
    }

    @Test func rejectsEntriesWithoutCertificate() {
        #expect(FTPCertificate(entries: ["Subject:CN = mc test"]) == nil)
        #expect(FTPCertificate(entries: ["Cert:-----BEGIN CERTIFICATE-----\n%%%\n-----END CERTIFICATE-----"]) == nil)
    }

    @Test func storesTrustedCertificatePerHostAndPort() throws {
        let store = FTPTrustStore(directory: NSTemporaryDirectory() + "nc-tests-" + UUID().uuidString + "/certs")
        let certificate = try #require(FTPCertificate(entries: ["Cert:" + pem]))
        #expect(store.trustedFile(host: "Example.org", port: 21) == nil)
        try store.trust(certificate, host: "Example.org", port: 21)
        let file = try #require(store.trustedFile(host: "example.org", port: 21))
        #expect(try String(contentsOfFile: file, encoding: .utf8) == certificate.pem)
        #expect(store.trustedFile(host: "example.org", port: 990) == nil)
        #expect(store.trustedFile(host: "../example.org", port: 21) == nil)
    }
}
