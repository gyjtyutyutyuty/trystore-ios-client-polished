import Foundation
import Security

enum PatchBundleKeyError: Error {
    case configuration
    case unauthorized
    case unavailable
    case secureStorage
}

/// Holds the key that unwraps bundled and feed patch content keys.
///
/// The key is not in the app bundle. It is released by the patch feed only
/// after the same licence and device check that guards the blobs, then cached
/// in the keychain for this device.
enum PatchBundleKeyStore {
    private static let service = "com.trystore.supportpatch.patch-bundle"
    private static let account = "bundle-key-v1"
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"

    private static let lock = NSLock()
    private static var cached: Data?

    static func cachedKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.count == 32 { return cached }
        guard let stored = readKeychain(), stored.count == 32 else { return nil }
        cached = stored
        return stored
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

        let url = baseURL.appendingPathComponent("api/patches/trystore/bundle-key")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

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
            let key: String
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.valid,
              let keyData = Data(base64Encoded: decoded.key),
              keyData.count == 32 else {
            throw PatchBundleKeyError.unavailable
        }

        try store(keyData)
        lock.lock()
        cached = keyData
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        cached = nil
        lock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    private static func store(_ key: Data) throws {
        guard key.count == 32 else { throw PatchBundleKeyError.secureStorage }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: key,
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
}
