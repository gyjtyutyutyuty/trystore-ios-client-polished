import CryptoKit
import Foundation
import Security

enum PatchKeyStore {
    private static let service = "com.trystore.supportpatch.patch-keys"
    /// The identifier this app was signed with before the move to its own bundle
    /// id. Items are only readable if the signing profile still carries this
    /// keychain access group; otherwise the lookup fails and the package simply
    /// asks for its password again.
    private static let legacyService = "com.apple.mobile.MobileHouseArrest.patch-keys"

    static func account(for summary: PatchPackageSummary) -> String {
        let fingerprint = summary.keyFingerprint.map { String(format: "%02x", $0) }.joined()
        return "\(summary.packageID.uuidString).\(fingerprint)"
    }

    static func store(_ contentKey: Data, for summary: PatchPackageSummary) throws {
        guard contentKey.count == 32,
              Data(SHA256.hash(data: contentKey)) == summary.keyFingerprint else {
            throw PatchPackageError.keychainFailed
        }
        let account = account(for: summary)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: contentKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw PatchPackageError.keychainFailed
        }

        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw PatchPackageError.keychainFailed
        }
    }

    static func load(for summary: PatchPackageSummary) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: summary),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            guard let legacy = readLegacy(account: account(for: summary)),
                  Data(SHA256.hash(data: legacy)) == summary.keyFingerprint else {
                return nil
            }
            try? store(legacy, for: summary)
            return legacy
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == 32,
              Data(SHA256.hash(data: data)) == summary.keyFingerprint else {
            throw PatchPackageError.keychainFailed
        }
        return data
    }

    static func delete(for summary: PatchPackageSummary) throws {
        for service in [service, legacyService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account(for: summary)
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PatchPackageError.keychainFailed
            }
        }
    }

    private static func readLegacy(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == 32 else {
            return nil
        }
        return data
    }
}
