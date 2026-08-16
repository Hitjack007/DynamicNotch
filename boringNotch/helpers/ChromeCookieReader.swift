//
//  ChromeCookieReader.swift
//  boringNotch
//
//  Reads claude.ai session cookies from Chromium-based browsers (Chrome, Brave, Edge).
//
//  Cookie values are AES-128-CBC encrypted with a key derived (PBKDF2-SHA1,
//  1003 iterations, 16-byte key, salt "saltysalt") from a password stored in
//  the macOS Keychain under each browser's "Safe Storage" service entry.
//  The encrypted_value column is prefixed with the 3-byte ASCII string "v10".
//

import CommonCrypto
import Foundation
import Security
import SQLite3

enum ChromeVariant {
    case chrome, brave, edge

    var cookiePath: String {
        let home = NSHomeDirectory()
        switch self {
        case .chrome: return "\(home)/Library/Application Support/Google/Chrome/Default/Cookies"
        case .brave:  return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies"
        case .edge:   return "\(home)/Library/Application Support/Microsoft Edge/Default/Cookies"
        }
    }

    var keychainService: String {
        switch self {
        case .chrome: return "Chrome Safe Storage"
        case .brave:  return "Brave Safe Storage"
        case .edge:   return "Microsoft Edge Safe Storage"
        }
    }

    var keychainAccount: String {
        switch self {
        case .chrome: return "Chrome"
        case .brave:  return "Brave"
        case .edge:   return "Microsoft Edge"
        }
    }
}

struct ChromeCookieReader {
    static func findClaudeSessionKey(variant: ChromeVariant) -> String? {
        findCookie(named: "sessionKey", variant: variant)
    }

    static func findCookie(named cookieName: String, variant: ChromeVariant) -> String? {
        guard let password = keychainPassword(for: variant),
              let key = deriveKey(from: password) else { return nil }
        return readEncryptedCookie(named: cookieName, variant: variant, key: key)
    }

    // MARK: - Keychain

    private static func keychainPassword(for variant: ChromeVariant) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: variant.keychainService,
            kSecAttrAccount as String: variant.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Key derivation (PBKDF2-SHA1)

    private static func deriveKey(from password: String) -> Data? {
        let salt = "saltysalt"
        var derived = Data(count: 16)
        let status: CCStatus = derived.withUnsafeMutableBytes { keyPtr in
            password.withCString { pwPtr in
                salt.withCString { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr, password.utf8.count,
                        UnsafeRawPointer(saltPtr).assumingMemoryBound(to: UInt8.self), salt.utf8.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyPtr.bindMemory(to: UInt8.self).baseAddress!, 16
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    // MARK: - SQLite

    private static func readEncryptedCookie(named cookieName: String, variant: ChromeVariant, key: Data) -> String? {
        guard FileManager.default.fileExists(atPath: variant.cookiePath) else { return nil }

        // Copy to avoid locking conflict with a running browser instance
        let tmp = NSTemporaryDirectory() + "boring_\(variant.keychainAccount)_cookies.db"
        try? FileManager.default.removeItem(atPath: tmp)
        guard (try? FileManager.default.copyItem(atPath: variant.cookiePath, toPath: tmp)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT encrypted_value FROM cookies
            WHERE host_key LIKE '%claude.ai%' AND name='\(cookieName)'
            ORDER BY creation_utc DESC LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let blob = sqlite3_column_blob(stmt, 0) else { return nil }
        let byteCount = Int(sqlite3_column_bytes(stmt, 0))
        guard byteCount > 3 else { return nil }

        let encrypted = Data(bytes: blob, count: byteCount)
        return decrypt(encrypted, key: key)
    }

    // MARK: - AES-128-CBC decryption

    private static func decrypt(_ data: Data, key: Data) -> String? {
        // Strip "v10" prefix
        guard data.count > 3,
              data[0] == 0x76, data[1] == 0x31, data[2] == 0x30 else { return nil }
        let ciphertext = data.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)  // 16 ASCII spaces

        let capacity = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: capacity)
        var decryptedLength = 0

        let status: CCCryptorStatus = plaintext.withUnsafeMutableBytes { outBuf in
            ciphertext.withUnsafeBytes { inBuf in
                iv.withUnsafeBytes { ivBuf in
                    key.withUnsafeBytes { keyBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, 16,
                            ivBuf.baseAddress,
                            inBuf.baseAddress, ciphertext.count,
                            outBuf.baseAddress, capacity,
                            &decryptedLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return String(data: plaintext.prefix(decryptedLength), encoding: .utf8)
    }
}
