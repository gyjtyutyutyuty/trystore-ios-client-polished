import CryptoKit
import DeviceCheck
import Foundation
import Security

enum PatchBundleKeyError: Error {
    case configuration
    case unauthorized
    case unavailable
    case attestationUnavailable
    case attestationRejected
    case secureStorage
}

/// Holds the key that unwraps bundled and feed patch content keys.
/// The server releases it only after license/device checks and a fresh App Attest assertion.
enum PatchBundleKeyStore {
    private static let service = "cc.forcequit.worse-query.patch-bundle"
    private static let account = "bundle-key-v1"
    private static let appAttestAccount = "app-attest-key-id-v1"
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"
    private static let bundleKeyPath = "/api/patches/trystore/bundle-key"
    private static let challengePath = "/api/patches/trystore/app-attest/challenge"
    private static let registrationPath = "/api/patches/trystore/app-attest/register"
    private static let appAttestService = DCAppAttestService.shared

    private static let lock = NSLock()
    private static var cached: Data?

    private struct Challenge: Decodable {
        let challengeId: String
        let challenge: String
        let mode: String
    }

    private struct KeyResponse: Decodable {
        let valid: Bool
        let key: String
        let keyVersion: String?
    }

    static func cachedKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.count == 32 { return cached }
        guard let stored = readKeychain(account: account), stored.count == 32 else { return nil }
        cached = stored
        return stored
    }

    static func refresh(licenseKey: String, deviceID: String) async throws {
        guard let baseURL = feedBaseURL() else { throw PatchBundleKeyError.configuration }
        guard appAttestService.isSupported else { throw PatchBundleKeyError.attestationUnavailable }

        var keyID = readStringKeychain(account: appAttestAccount)
        var challenge = try await requestChallenge(baseURL: baseURL, licenseKey: licenseKey, deviceID: deviceID, keyID: keyID)
        if challenge.mode == "attest" {
            // A server-side reset or a reinstall can leave a stale key identifier.
            // A newly generated Secure Enclave key must be attested before use.
            keyID = try await generateKey()
            let challengeBytes = try decodeChallenge(challenge.challenge)
            let challengeHash = Data(SHA256.hash(data: challengeBytes))
            let attestation = try await attest(keyID: keyID, clientDataHash: challengeHash)
            try await register(
                baseURL: baseURL,
                licenseKey: licenseKey,
                deviceID: deviceID,
                challenge: challenge,
                keyID: keyID,
                attestation: attestation
            )
            try storeString(keyID, account: appAttestAccount)
            challenge = try await requestChallenge(
                baseURL: baseURL,
                licenseKey: licenseKey,
                deviceID: deviceID,
                keyID: keyID
            )
        }
        guard challenge.mode == "assertion", let keyID else {
            throw PatchBundleKeyError.attestationRejected
        }

        let clientData = assertionClientData(challenge: challenge, deviceID: deviceID)
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let assertion = try await generateAssertion(keyID: keyID, clientDataHash: clientDataHash)
        let payload: [String: Any] = [
            "challengeID": challenge.challengeId,
            "challenge": challenge.challenge,
            "keyId": keyID,
            "assertion": assertion.base64EncodedString()
        ]
        let data = try await postJSON(
            baseURL: baseURL,
            path: bundleKeyPath,
            payload: payload,
            licenseKey: licenseKey,
            deviceID: deviceID
        )
        let response: KeyResponse
        do {
            response = try JSONDecoder().decode(KeyResponse.self, from: data)
        } catch {
            throw PatchBundleKeyError.unavailable
        }
        guard response.valid,
              let keyData = Data(base64Encoded: response.key),
              keyData.count == 32 else {
            throw PatchBundleKeyError.attestationRejected
        }
        try store(keyData)
        lock.lock()
        cached = keyData
        lock.unlock()
    }

    static func clear() {
        invalidateBundleKey()
        deleteKeychainItem(account: appAttestAccount)
    }

    static func invalidateBundleKey() {
        lock.lock()
        cached = nil
        lock.unlock()
        deleteKeychainItem(account: account)
    }

    private static func feedBaseURL() -> URL? {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PATCH_FEED_URL") as? String,
              let baseURL = URL(string: configured),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host?.lowercased() == expectedHost,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil else {
            return nil
        }
        return baseURL
    }

    private static func requestChallenge(
        baseURL: URL,
        licenseKey: String,
        deviceID: String,
        keyID: String?
    ) async throws -> Challenge {
        var payload: [String: Any] = [:]
        if let keyID { payload["keyId"] = keyID }
        let data = try await postJSON(
            baseURL: baseURL,
            path: challengePath,
            payload: payload,
            licenseKey: licenseKey,
            deviceID: deviceID
        )
        do {
            let challenge = try JSONDecoder().decode(Challenge.self, from: data)
            guard !challenge.challengeId.isEmpty,
                  !challenge.challenge.isEmpty,
                  challenge.mode == "attest" || challenge.mode == "assertion" else {
                throw PatchBundleKeyError.attestationRejected
            }
            return challenge
        } catch let error as PatchBundleKeyError {
            throw error
        } catch {
            throw PatchBundleKeyError.unavailable
        }
    }

    private static func register(
        baseURL: URL,
        licenseKey: String,
        deviceID: String,
        challenge: Challenge,
        keyID: String,
        attestation: Data
    ) async throws {
        let payload: [String: Any] = [
            "challengeID": challenge.challengeId,
            "challenge": challenge.challenge,
            "keyId": keyID,
            "attestation": attestation.base64EncodedString()
        ]
        let data = try await postJSON(
            baseURL: baseURL,
            path: registrationPath,
            payload: payload,
            licenseKey: licenseKey,
            deviceID: deviceID
        )
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["valid"] as? Bool == true else {
            throw PatchBundleKeyError.attestationRejected
        }
    }

    private static func postJSON(
        baseURL: URL,
        path: String,
        payload: [String: Any],
        licenseKey: String,
        deviceID: String
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host?.lowercased() == expectedHost else {
            throw PatchBundleKeyError.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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
        guard let http = response as? HTTPURLResponse,
              http.url?.host?.lowercased() == expectedHost else {
            throw PatchBundleKeyError.unavailable
        }
        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 409 {
            throw PatchBundleKeyError.unauthorized
        }
        guard http.statusCode == 200 else { throw PatchBundleKeyError.unavailable }
        return data
    }

    private static func assertionClientData(challenge: Challenge, deviceID: String) -> Data {
        let value = [
            "TryStore App Attest v1",
            challenge.challengeId,
            challenge.challenge,
            "POST",
            bundleKeyPath,
            deviceID
        ].joined(separator: "\n")
        return Data(value.utf8)
    }

    private static func decodeChallenge(_ value: String) throws -> Data {
        guard let data = Data(base64Encoded: value), data.count == 32 else {
            throw PatchBundleKeyError.attestationRejected
        }
        return data
    }

    private static func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateKey { keyID, error in
                if let error { continuation.resume(throwing: error); return }
                guard let keyID, !keyID.isEmpty else {
                    continuation.resume(throwing: PatchBundleKeyError.attestationUnavailable)
                    return
                }
                continuation.resume(returning: keyID)
            }
        }
    }

    private static func attest(keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.attestKey(keyID, clientDataHash: clientDataHash) { attestation, error in
                if let error { continuation.resume(throwing: error); return }
                guard let attestation, !attestation.isEmpty else {
                    continuation.resume(throwing: PatchBundleKeyError.attestationUnavailable)
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
    }

    private static func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
                if let error { continuation.resume(throwing: error); return }
                guard let assertion, !assertion.isEmpty else {
                    continuation.resume(throwing: PatchBundleKeyError.attestationUnavailable)
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
    }

    private static func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private static func readStringKeychain(account: String) -> String? {
        guard let data = readKeychain(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func store(_ key: Data) throws {
        guard key.count == 32 else { throw PatchBundleKeyError.secureStorage }
        try storeData(key, account: account)
    }

    private static func storeString(_ value: String, account: String) throws {
        try storeData(Data(value.utf8), account: account)
    }

    private static func storeData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw PatchBundleKeyError.secureStorage }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw PatchBundleKeyError.secureStorage
        }
    }

    private static func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
