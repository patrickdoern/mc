import Foundation
import Security
import Testing
@testable import MCCore

private func makeKey() throws -> SecKey {
    let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits as String: 256]
    return try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
}

private func makeCertificate(_ key: SecKey) throws -> SecCertificate {
    try #require(SecCertificateCreateWithData(nil, try LinkIdentity.certificateData(for: key, issuedAt: Date()) as CFData))
}

@Suite(.serialized) struct LinkIdentityTests {
    @Test func certificateIsReadableAndSelfSigned() throws {
        let certificate = try makeCertificate(try makeKey())
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == "Moonlight Commander")
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        let evaluated = try #require(trust)
        SecTrustSetAnchorCertificates(evaluated, [certificate] as CFArray)
        #expect(SecTrustEvaluateWithError(evaluated, nil))
    }

    @Test func certificateKeyVerifiesSignatureOfPrivateKey() throws {
        let key = try makeKey()
        let publicKey = try #require(SecCertificateCopyKey(try makeCertificate(key)))
        let message = Data("Moonlight Commander".utf8)
        let signature = try #require(SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, nil))
        #expect(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, message as CFData, signature, nil))
    }

    @Test func identityIsCreatedOnceAndReused() throws {
        let label = "digital.doern.mc.link.test." + UUID().uuidString
        defer { LinkIdentity.remove(label: label) }
        let first = try LinkIdentity.load(label: label)
        let second = try LinkIdentity.load(label: label)
        #expect(first.fingerprint == second.fingerprint)
        var stored: SecKey?
        #expect(SecIdentityCopyPrivateKey(second.identity, &stored) == errSecSuccess)
        let key = try #require(stored)
        let publicKey = try #require(SecCertificateCopyKey(second.certificate))
        let message = Data("hello".utf8)
        let signature = try #require(SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, nil))
        #expect(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, message as CFData, signature, nil))
    }

    @Test func removedIdentityLeavesNothingInKeychain() throws {
        let label = "digital.doern.mc.link.test." + UUID().uuidString
        let identity = try LinkIdentity.load(label: label)
        LinkIdentity.remove(label: label)
        var certificates: CFTypeRef?
        #expect(SecItemCopyMatching([kSecClass as String: kSecClassCertificate, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitAll] as CFDictionary, &certificates) == errSecSuccess)
        #expect(!((certificates as? [SecCertificate]) ?? []).contains { LinkIdentity.fingerprint(of: $0) == identity.fingerprint })
        #expect(SecItemCopyMatching([kSecClass as String: kSecClassKey, kSecAttrLabel as String: label] as CFDictionary, nil) == errSecItemNotFound)
    }

    @Test func fingerprintIsSHA256OfCertificate() throws {
        let certificate = try makeCertificate(try makeKey())
        #expect(LinkIdentity.fingerprint(of: certificate).count == 32)
        #expect(LinkIdentity.fingerprint(of: certificate) == LinkIdentity.fingerprint(of: certificate))
    }

    @Test func pairingCodeIsSameOnBothSides() throws {
        let own = LinkIdentity.fingerprint(of: try makeCertificate(try makeKey()))
        let peer = LinkIdentity.fingerprint(of: try makeCertificate(try makeKey()))
        let other = LinkIdentity.fingerprint(of: try makeCertificate(try makeKey()))
        #expect(LinkIdentity.pairingCode(own, peer) == LinkIdentity.pairingCode(peer, own))
        #expect(LinkIdentity.pairingCode(own, peer) != LinkIdentity.pairingCode(own, other))
    }

    @Test func pairingCodeHasSixDigitsWithLeadingZeros() {
        #expect(LinkIdentity.pairingCode(Data([0x04]), Data([0xFF])) == "014 921")
        #expect(LinkIdentity.pairingCode(Data([0xFF]), Data([0x04])) == "014 921")
    }
}
