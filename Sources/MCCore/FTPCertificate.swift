import CryptoKit
import Foundation

public struct FTPCertificate: Equatable {
    public let pem: String
    public let subject: String?
    public let issuer: String?
    public let expires: String?

    init?(entries: [String]) {
        var values: [String: String] = [:]
        for entry in entries {
            guard let colon = entry.firstIndex(of: ":") else { continue }
            let key = String(entry[..<colon])
            if values[key] == nil { values[key] = String(entry[entry.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard let pem = values["Cert"], pem.contains("BEGIN CERTIFICATE"), Self.der(of: pem) != nil else { return nil }
        self.pem = pem.hasSuffix("\n") ? pem : pem + "\n"
        subject = values["Subject"]
        issuer = values["Issuer"]
        expires = values["Expire date"]
    }

    public var fingerprint: String {
        guard let der = Self.der(of: pem) else { return "" }
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func der(of pem: String) -> Data? {
        let body = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: body)
    }
}

public struct FTPTrustStore {
    let directory: String

    public static let standard = FTPTrustStore(directory: NSHomeDirectory() + "/.config/moonlight-commander/ftp-certificates")

    init(directory: String) {
        self.directory = directory
    }

    func trustedFile(host: String, port: Int) -> String? {
        let path = file(host: host, port: port)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func trust(_ certificate: FTPCertificate, host: String, port: Int) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(certificate.pem.utf8).write(to: URL(fileURLWithPath: file(host: host, port: port)), options: .atomic)
    }

    private func file(host: String, port: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let name = String(host.lowercased().map { allowed.contains($0) ? $0 : "_" })
        return directory + "/" + name + "_" + String(port) + ".pem"
    }
}
