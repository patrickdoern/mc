import Foundation
import Security

enum Keychain {
    private static let service = "digital.doern.mc.sftp"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func password(for account: String) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account).merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { $1 } as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ password: String, for account: String) {
        let data = Data(password.utf8)
        if SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(account).merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    static func accounts() -> [String] {
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query("").filter { $0.key != kSecAttrAccount as String }.merging([kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]) { $1 } as CFDictionary, &items)
        guard status == errSecSuccess, let attributes = items as? [[String: Any]] else { return [] }
        return attributes.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }
}
