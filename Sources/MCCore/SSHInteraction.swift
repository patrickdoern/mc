public struct PasswordEntry {
    public let password: String
    public let remember: Bool

    public init(password: String, remember: Bool) {
        self.password = password
        self.remember = remember
    }
}

public protocol SSHInteraction: AnyObject {
    func trustUnknownHost(_ host: String, keyType: String, fingerprint: String) -> Bool
    func allowUnencryptedLogin(_ host: String) -> Bool
    func trustCertificate(_ host: String, certificate: FTPCertificate, changed: Bool) -> Bool
    func requestSecret(_ prompt: String) -> String?
    func requestPassword(_ prompt: String, account: String) -> PasswordEntry?
    func storedPassword(for account: String) -> String?
    func savePassword(_ password: String, for account: String)
    func deletePassword(for account: String)
}
