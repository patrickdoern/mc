import CryptoKit
import Foundation
import Security

public struct LinkIdentity {
    public static let standardLabel = "digital.doern.mc.link"

    public let identity: SecIdentity
    public let certificate: SecCertificate

    public var fingerprint: Data { Self.fingerprint(of: certificate) }

    private static let keychainLock = NSLock()

    public static func load(label: String = standardLabel) throws -> LinkIdentity {
        try keychainLock.withLock {
            if let certificate = storedCertificate(label: label), let identity = identity(for: certificate) {
                return LinkIdentity(identity: identity, certificate: certificate)
            }
            removeStored(label: label)
            return try create(label: label)
        }
    }

    private static func create(label: String) throws -> LinkIdentity {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrLabel as String: label],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw failure(error) }
        guard let certificate = SecCertificateCreateWithData(nil, try certificateData(for: key, issuedAt: Date()) as CFData) else { throw failure(errSecDecode) }
        let status = SecItemAdd([kSecClass as String: kSecClassCertificate, kSecValueRef as String: certificate] as CFDictionary, nil)
        guard status == errSecSuccess else { throw failure(status) }
        guard let identity = identity(for: certificate) else { throw failure(errSecItemNotFound) }
        return LinkIdentity(identity: identity, certificate: certificate)
    }

    public static func fingerprint(of certificate: SecCertificate) -> Data {
        Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    public static func pairingCode(_ first: Data, _ second: Data) -> String {
        let joined = [first, second].sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +)
        let value = SHA256.hash(data: joined).prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } % 1_000_000
        return String(format: "%03d %03d", Int(value / 1000), Int(value % 1000))
    }

    static func remove(label: String) {
        keychainLock.withLock { removeStored(label: label) }
    }

    private static func removeStored(label: String) {
        if let certificate = storedCertificate(label: label) {
            SecItemDelete([kSecClass as String: kSecClassCertificate, kSecValueRef as String: certificate] as CFDictionary)
        }
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrLabel as String: label] as CFDictionary)
    }

    static func certificateData(for privateKey: SecKey, issuedAt date: Date) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey), let point = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { throw failure(error) }
        let signatureAlgorithm = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([0x55, 0x04, 0x03]) + DER.element(0x0C, Data("Moonlight Commander".utf8)))))
        var serial = (0..<16).map { _ in UInt8.random(in: 0...255) }
        serial[0] = serial[0] & 0x7F | 0x40
        let start = date.addingTimeInterval(-86_400)
        let end = start.addingTimeInterval(20 * 365 * 86_400)
        let publicKeyInfo = DER.sequence(
            DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]) + DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]))
                + DER.bitString(point)
        )
        let keyUsage = DER.sequence(DER.oid([0x55, 0x1D, 0x0F]) + DER.element(0x01, Data([0xFF])) + DER.element(0x04, DER.element(0x03, Data([0x07, 0x80]))))
        let extendedKeyUsage = DER.sequence(DER.oid([0x55, 0x1D, 0x25]) + DER.element(0x04, DER.sequence(
            DER.oid([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]) + DER.oid([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])
        )))
        let certificate = DER.sequence(
            DER.element(0xA0, DER.element(0x02, Data([0x02])))
                + DER.element(0x02, Data(serial))
                + signatureAlgorithm
                + name
                + DER.sequence(DER.time(start) + DER.time(end))
                + name
                + publicKeyInfo
                + DER.element(0xA3, DER.sequence(keyUsage + extendedKeyUsage))
        )
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, certificate as CFData, &error) as Data? else { throw failure(error) }
        return DER.sequence(certificate + signatureAlgorithm + DER.bitString(signature))
    }

    private static func storedCertificate(label: String) -> SecCertificate? {
        var key: CFTypeRef?
        let keyQuery: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrLabel as String: label, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(keyQuery as CFDictionary, &key) == errSecSuccess, let hash = (key as? [String: Any])?[kSecAttrApplicationLabel as String] as? Data else { return nil }
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecAttrPublicKeyHash as String: hash, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item, CFGetTypeID(item) == SecCertificateGetTypeID() else { return nil }
        return (item as! SecCertificate)
    }

    private static func identity(for certificate: SecCertificate) -> SecIdentity? {
        var identity: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess else { return nil }
        return identity
    }

    private static func failure(_ error: Unmanaged<CFError>?) -> FileError {
        failure(OSStatus(error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? Int(errSecParam)))
    }

    private static func failure(_ status: OSStatus) -> FileError {
        FileError(localized("Die Identität für die Direktverbindung lässt sich nicht im Schlüsselbund anlegen (Fehler %ld)", Int(status)))
    }
}

private enum DER {
    static func element(_ tag: UInt8, _ content: Data) -> Data {
        var length = Data()
        if content.count < 0x80 {
            length.append(UInt8(content.count))
        } else {
            var count = content.count
            while count > 0 {
                length.insert(UInt8(count & 0xFF), at: 0)
                count >>= 8
            }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return Data([tag]) + length + content
    }

    static func sequence(_ content: Data) -> Data { element(0x30, content) }

    static func set(_ content: Data) -> Data { element(0x31, content) }

    static func oid(_ bytes: [UInt8]) -> Data { element(0x06, Data(bytes)) }

    static func bitString(_ content: Data) -> Data { element(0x03, Data([0x00]) + content) }

    static func time(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = parts.year ?? 0
        let rest = String(format: "%02d%02d%02d%02d%02dZ", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return year < 2050 ? element(0x17, Data((String(format: "%02d", year % 100) + rest).utf8)) : element(0x18, Data((String(year) + rest).utf8))
    }
}
