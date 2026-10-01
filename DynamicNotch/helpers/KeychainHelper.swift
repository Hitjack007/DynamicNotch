//
//  KeychainHelper.swift
//  DynamicNotch
//

import Foundation
import Security

struct KeychainHelper {
    private static let service = "com.boringnotch.claude"

    /// Writes a credential to the Keychain.
    /// - Returns: `true` when the item was stored. Callers must not report success
    ///   to the user on `false` — the previous value has already been removed at
    ///   that point, so the credential is simply gone.
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.keychain.error("Keychain save failed for account \(account), OSStatus=\(status)")
        }
        return status == errSecSuccess
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            // errSecItemNotFound (-25300) is the expected/common case (nothing saved
            // yet) - only worth a debug log, not error, to avoid spamming on every
            // startup before the user has authenticated.
            if status != errSecItemNotFound {
                AppLogger.keychain.error("Keychain load failed for account \(account), OSStatus=\(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
