import CryptoKit
import Foundation
import Security

enum PatchBundleKeyError: Error {
    case configuration
    case unauthorized
    case unavailable
    case secureStorage
}

/// Keeps the feed's shared wrapping key out of the IPA and Keychain.
/// The worker returns it only inside an ECDH envelope addressed to this
/// installation's Secure Enclave key; the unwrapped value lives in memory only.
enum PatchBundleKeyStore {
    private static let service = "cc.forcequit.worse-query.patch-bundle"
    private static let legacyAccount = "bundle-key-v1"
    private static let deviceKeyService = "cc.forcequit.worse-query.patch-device-ecdh"
    private static let deviceKeyAccount = "p256-key-v2"
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"
    private static let envelopeScheme = "p256-hkdf-sha256-aesgcm-v2"

    private static let lock = NSLock()
    private static var cached: Data?

    static func cachedKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached, cached.count == 32 else { return nil }
        return cached
    }

    static func refresh(licenseKey: String, deviceID: String) async throws {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PATCH_FEED_URL") as? String,
              let baseURL = URL(string: configured),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host?.lowercased() == expectedHost,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil else {
            throw PatchBundleKeyError.configuration
        }

        deleteLegacyStoredKey()
        let privateKey = try devicePrivateKey()
        let publicKey = privateKey.publicKey.x963Representation
        let url = baseURL.appendingPathComponent("api/patches/trystore/bundle-key")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "publicKey": publicKey.base64EncodedString()
        ])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PatchBundleKeyError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw PatchBundleKeyError.unavailable
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PatchBundleKeyError.unauthorized
        }
        guard http.statusCode == 200,
              http.url?.host?.lowercased() == expectedHost else {
            throw PatchBundleKeyError.unavailable
        }

        struct Response: Decodable {
            let valid: Bool
            let scheme: String
            let keyVersion: Int
            let ephemeralPublicKey: String
            let salt: String
            let nonce: String
            let ciphertext: String
        }
        guard let envelope = try? JSONDecoder().decode(Response.self, from: data),
              envelope.valid,
              envelope.scheme == envelopeScheme,
              envelope.keyVersion == 2,
              let ephemeralBytes = Data(base64Encoded: envelope.ephemeralPublicKey),
              let salt = Data(base64Encoded: envelope.salt), salt.count == 16,
              let nonceData = Data(base64Encoded: envelope.nonce), nonceData.count == 12,
              let encrypted = Data(base64Encoded: envelope.ciphertext), encrypted.count == 48 else {
            throw PatchBundleKeyError.unavailable
        }

        do {
            let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralBytes)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
            let info = envelopeInfo(deviceID: deviceID)
            let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: info,
                outputByteCount: 32
            )
            let tag = Data(encrypted.suffix(16))
            let ciphertext = Data(encrypted.dropLast(16))
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let keyData = try AES.GCM.open(box, using: wrappingKey, authenticating: info)
            guard keyData.count == 32 else { throw PatchBundleKeyError.unavailable }

            // Remove the older shared-key-at-rest copy left by prior app versions.
            deleteLegacyStoredKey()
            cacheKey(keyData)
        } catch let error as PatchBundleKeyError {
            throw error
        } catch {
            throw PatchBundleKeyError.unavailable
        }
    }

    static func clear() {
        lock.lock()
        cached = nil
        lock.unlock()
        deleteLegacyStoredKey()
        deleteDevicePrivateKey()
    }

    private static func cacheKey(_ key: Data) {
        lock.lock()
        defer { lock.unlock() }
        cached = key
    }

    private static func envelopeInfo(deviceID: String) -> Data {
        Data("trystore-patch-feed|bundle-key|v2|trystore|\(deviceID.lowercased())".utf8)
    }

    private static func devicePrivateKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        if let saved = readDevicePrivateKey(),
           let existing = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: saved) {
            return existing
        }
        deleteDevicePrivateKey()
        do {
            let created = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            try storeDevicePrivateKey(created.dataRepresentation)
            return created
        } catch {
            throw PatchBundleKeyError.secureStorage
        }
    }

    private static func readDevicePrivateKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceKeyService,
            kSecAttrAccount as String: deviceKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    private static func storeDevicePrivateKey(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceKeyService,
            kSecAttrAccount as String: deviceKeyAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw PatchBundleKeyError.secureStorage
        }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw PatchBundleKeyError.secureStorage
        }
    }

    private static func deleteDevicePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceKeyService,
            kSecAttrAccount as String: deviceKeyAccount
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    private static func deleteLegacyStoredKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
