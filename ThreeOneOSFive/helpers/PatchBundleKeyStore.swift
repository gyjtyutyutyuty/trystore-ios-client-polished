import CryptoKit
import DeviceCheck
import Foundation
import Security

extension Notification.Name {
    /// Posted after a bundle key is cached. Views that materialize sealed
    /// bundled art listen for this instead of staying blank until relaunch.
    static let patchBundleKeyDidChange = Notification.Name("cc.forcequit.worse-query.patch-bundle-key")
}

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
    private static let expiryAccount = "bundle-key-expiry-v1"
    private static let feedTokenAccount = "feed-token-v1"
    private static let feedTokenExpiryAccount = "feed-token-expiry-v1"
    private static let keyVersionAccount = "bundle-key-version-v1"
    private static let appAttestAccount = "app-attest-key-id-v1"
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"
    private static let bundleKeyPath = "/api/patches/trystore/bundle-key"
    private static let deviceChallengePath = "/api/patches/trystore/device-challenge"
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
        let expiresAt: String?
        let feedToken: String?
        let tokenExpiresAt: String?
    }

    static func cachedKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard validUntil(account: expiryAccount) else {
            cached = nil
            deleteKeychainItem(account: account)
            return nil
        }
        if let cached, cached.count == 32 { return cached }
        guard let stored = readKeychain(account: account), stored.count == 32 else { return nil }
        cached = stored
        return stored
    }

    /// Short-lived token issued with the bundle key. The feed accepts it for
    /// manifests and blobs without re-running the licence check per request.
    static func cachedFeedToken() -> String? {
        guard validUntil(account: feedTokenExpiryAccount) else {
            deleteKeychainItem(account: feedTokenAccount)
            return nil
        }
        return readStringKeychain(account: feedTokenAccount)
    }

    /// Version the cached key was released under. Used in sync diagnostics; the
    /// vault manifest's fingerprint is the authoritative check.
    static func cachedKeyVersion() -> String? {
        guard cachedKey() != nil else { return nil }
        return readStringKeychain(account: keyVersionAccount)
    }

    static func refresh(licenseKey: String, deviceID: String) async throws {
        guard let baseURL = feedBaseURL() else { throw PatchBundleKeyError.configuration }

        // App Attest is the preferred path. A sideloaded or self-signed build
        // cannot always attest (missing entitlement, development profile, or a
        // re-signed bundle), and refusing to activate over that leaves the art
        // unreadable on hardware that is otherwise licensed. Fall back to a
        // release bound to the live licence and device instead of failing the
        // whole activation.
        if appAttestService.isSupported {
            do {
                try await refreshWithAttestation(
                    baseURL: baseURL,
                    licenseKey: licenseKey,
                    deviceID: deviceID
                )
                return
            } catch let error as PatchBundleKeyError {
                switch error {
                case .configuration, .secureStorage:
                    throw error
                case .unauthorized, .unavailable, .attestationUnavailable, .attestationRejected:
                    // A rejected assertion is not a rejected licence. The
                    // challenge and bundle-key calls below re-check the licence
                    // and the device themselves, so attestation failures must
                    // never short-circuit the licensed release.
                    break
                }
                log("patches: App Attest path failed (\(error)); trying the licence-bound release")
            } catch {
                log("patches: App Attest path failed (\(error)); trying the licence-bound release")
            }
        }
        try await refreshWithLicence(baseURL: baseURL, licenseKey: licenseKey, deviceID: deviceID)
    }

    private static func refreshWithAttestation(
        baseURL: URL,
        licenseKey: String,
        deviceID: String
    ) async throws {
        var keyID = readStringKeychain(account: appAttestAccount)
        var challenge = try await requestChallenge(baseURL: baseURL, licenseKey: licenseKey, deviceID: deviceID, keyID: keyID)
        if challenge.mode == "attest" {
            // A server-side reset or a reinstall can leave a stale key identifier.
            // A newly generated Secure Enclave key must be attested before use.
            // Keep the generated value non-optional; assigning it to the optional
            // variable above would not narrow the type inside this branch.
            let attestedKeyID = try await generateKey()
            keyID = attestedKeyID
            let challengeBytes = try decodeChallenge(challenge.challenge)
            let challengeHash = Data(SHA256.hash(data: challengeBytes))
            let attestation = try await attest(keyID: attestedKeyID, clientDataHash: challengeHash)
            do {
                try await register(
                    baseURL: baseURL,
                    licenseKey: licenseKey,
                    deviceID: deviceID,
                    challenge: challenge,
                    keyID: attestedKeyID,
                    attestation: attestation
                )
            } catch PatchBundleKeyError.unauthorized {
                // A conflict or rejection here is the attestation flow, not a
                // dead licence: fall back to the licence-bound release.
                throw PatchBundleKeyError.attestationRejected
            }
            try storeString(attestedKeyID, account: appAttestAccount)
            challenge = try await requestChallenge(
                baseURL: baseURL,
                licenseKey: licenseKey,
                deviceID: deviceID,
                keyID: attestedKeyID
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
        let data: Data
        do {
            data = try await postJSON(
                baseURL: baseURL,
                path: bundleKeyPath,
                payload: payload,
                licenseKey: licenseKey,
                deviceID: deviceID
            )
        } catch PatchBundleKeyError.unauthorized {
            throw PatchBundleKeyError.attestationRejected
        }
        try acceptKeyResponse(data)
    }

    /// Release for builds that cannot produce an App Attest assertion. The feed
    /// still validates the licence and device binding before it hands out the
    /// key, so a stolen or expired licence gets nothing. When the device can
    /// sign a challenge with its P-256 key the proof travels too, so a copied
    /// device UUID does not pass for the original phone.
    private static func refreshWithLicence(
        baseURL: URL,
        licenseKey: String,
        deviceID: String
    ) async throws {
        var headers: [String: String] = ["X-TryStore-Attestation-Mode": "licence"]
        if let proof = try? await deviceProof(
            baseURL: baseURL,
            licenseKey: licenseKey,
            deviceID: deviceID
        ) {
            headers.merge(proof) { _, new in new }
        }
        let data = try await postJSON(
            baseURL: baseURL,
            path: bundleKeyPath,
            payload: [:],
            licenseKey: licenseKey,
            deviceID: deviceID,
            extraHeaders: headers
        )
        try acceptKeyResponse(data)
    }

    private static func deviceProof(
        baseURL: URL,
        licenseKey: String,
        deviceID: String
    ) async throws -> [String: String] {
        let publicKey = try DeviceKey.publicKeyBase64()
        let challenge = try await requestDeviceChallenge(
            baseURL: baseURL,
            licenseKey: licenseKey,
            deviceID: deviceID
        )
        let message = DeviceKey.message(
            challenge: challenge,
            project: "trystore",
            deviceID: deviceID
        )
        let signature = try DeviceKey.signature(message: message)
        return [
            "X-TryStore-Device-Public-Key": publicKey,
            "X-TryStore-Device-Signature": signature,
            "X-TryStore-Challenge": challenge
        ]
    }

    private static func requestDeviceChallenge(
        baseURL: URL,
        licenseKey: String,
        deviceID: String
    ) async throws -> String {
        guard let url = URL(string: deviceChallengePath, relativeTo: baseURL)?.absoluteURL,
              url.host?.lowercased() == expectedHost else {
            throw PatchBundleKeyError.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any],
              let challenge = object["challenge"] as? String,
              !challenge.isEmpty,
              challenge.count <= 256 else {
            throw PatchBundleKeyError.unavailable
        }
        return challenge
    }

    private static func acceptKeyResponse(_ data: Data) throws {
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
        let keyExpiry = epoch(from: response.expiresAt) ?? (Date().timeIntervalSince1970 + 86_400)
        try storeString(String(Int(keyExpiry)), account: expiryAccount)
        if let version = response.keyVersion, !version.isEmpty, version.count <= 8 {
            try storeString(version, account: keyVersionAccount)
        } else {
            deleteKeychainItem(account: keyVersionAccount)
        }
        if let token = response.feedToken, !token.isEmpty,
           let tokenExpiry = epoch(from: response.tokenExpiresAt) {
            try storeString(token, account: feedTokenAccount)
            try storeString(String(Int(tokenExpiry)), account: feedTokenExpiryAccount)
        } else {
            deleteKeychainItem(account: feedTokenAccount)
            deleteKeychainItem(account: feedTokenExpiryAccount)
        }
        cacheKey(keyData)
        NotificationCenter.default.post(name: .patchBundleKeyDidChange, object: nil)
    }

    private static func cacheKey(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        cached = data
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
        deleteKeychainItem(account: expiryAccount)
        deleteKeychainItem(account: keyVersionAccount)
        deleteKeychainItem(account: feedTokenAccount)
        deleteKeychainItem(account: feedTokenExpiryAccount)
    }

    private static func validUntil(account: String) -> Bool {
        guard let raw = readStringKeychain(account: account), let expiry = Double(raw) else {
            return false
        }
        return expiry > Date().timeIntervalSince1970
    }

    private static func epoch(from value: String?) -> TimeInterval? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date.timeIntervalSince1970 }
        return ISO8601DateFormatter().date(from: value)?.timeIntervalSince1970
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
        deviceID: String,
        extraHeaders: [String: String] = [:]
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
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // A dropped connection or a cold Worker start used to end the whole
        // sync. Retry the transport, but surface a rejected licence at once
        // and never retry a keychain write: those answers do not change.
        var lastError = PatchBundleKeyError.unavailable
        for attempt in 0..<3 {
            do {
                return try await fetchAndCacheBundleKey(request: request, session: session)
            } catch let error as PatchBundleKeyError {
                lastError = error
                switch error {
                case .unauthorized, .configuration, .secureStorage,
                     .attestationUnavailable, .attestationRejected:
                    throw error
                case .unavailable:
                    break
                }
            } catch {
                lastError = .unavailable
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
            }
        }
        throw lastError
    }

    private static func fetchAndCacheBundleKey(
        request: URLRequest,
        session: URLSession
    ) async throws -> Data {
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
