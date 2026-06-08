import Foundation
import Security

/// A small generic-password Keychain wrapper. Helm stores all SSH secrets here —
/// private keys, passphrases, passwords, and the optional Tailscale API key — never
/// in UserDefaults. Items are keyed by a string account within Helm's service.
struct KeychainStore {
    let service: String

    init(service: String = "org.scty.helm.credentials") {
        self.service = service
    }

    @discardableResult
    func set(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return delete(account: account)
        }

        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            // SSH key material stays on this device (never syncs to iCloud Keychain) and
            // is readable after first unlock so background reconnects work while locked.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }

        return status == errSecSuccess
    }

    func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Stable Keychain account names for a host's secrets.
enum HostSecret {
    static func privateKey(_ id: UUID) -> String { "host.\(id.uuidString).privateKey" }
    static func passphrase(_ id: UUID) -> String { "host.\(id.uuidString).passphrase" }
    static func password(_ id: UUID) -> String { "host.\(id.uuidString).password" }

    static func all(_ id: UUID) -> [String] {
        [privateKey(id), passphrase(id), password(id)]
    }
}
