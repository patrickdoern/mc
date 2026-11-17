public protocol SSHInteraction: AnyObject {
    func trustUnknownHost(_ host: String, keyType: String, fingerprint: String) -> Bool
    func requestSecret(_ prompt: String) -> String?
}
