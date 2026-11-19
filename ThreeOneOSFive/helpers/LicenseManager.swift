import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var isOffline = false
    @Published private(set) var expirationDate: Date?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var messageKey: String?
    @Published private(set) var maskedKey: String?

    private let keychainService = "com.trystore.license"
    private let keyAccount = "license-key"
    private let deviceAccount = "device-id"
    private let defaultEndpoint = "https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate"

    /// The licence answer decides whether the app unlocks, so the host that
    /// gives it is pinned here. Editing Info.plist can point a build at another
    /// server, but that server's answer is only accepted if it speaks for this
    /// host, which an attacker does not control.
    private let trustedLicenseHost = "jvztxnx-global-control.burgoajustin.workers.dev"

    private var endpoint: URL? {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_LICENSE_API_URL") as? String
        let value = (configured?.isEmpty == false ? configured : defaultEndpoint) ?? defaultEndpoint
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.host?.lowercased() == trustedLicenseHost else {
            return nil
        }
        return url
    }

    private var projectID: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PROJECT_ID") as? String
        return configured?.isEmpty == false ? configured! : "trystore"
    }

    var hasSavedKey: Bool { keychainString(for: keyAccount) != nil }

    func patchFeedCredentials() -> PatchFeedCredentials? {
        guard isActive,
              let key = keychainString(for: keyAccount), !key.isEmpty,
              let identifier = try? deviceID(), !identifier.isEmpty else {
            return nil
        }
        return PatchFeedCredentials(licenseKey: key, deviceID: identifier)
    }

    func beginLaunchSession() {
        guard !isBusy else { return }
        guard let key = keychainString(for: keyAccount), !key.isEmpty else {
            PatchBundleKeyStore.clear()
            isActive = false
            expirationDate = nil
            maskedKey = nil
            messageKey = nil
            return
        }
        if isActive, let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < 45 {
            return
        }
        isActive = false
        validate(key: key, persistOnSuccess: false)
    }

    func activate(key rawKey: String) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty, !isBusy else { return }
        validate(key: key, persistOnSuccess: true)
    }

    func refresh() {
        guard !isBusy else { return }
        guard let key = keychainString(for: keyAccount), !key.isEmpty else {
            isActive = false
            messageKey = "license.error_required"
            return
        }
        isActive = false
        validate(key: key, persistOnSuccess: false)
    }

    func clear() {
        deleteKeychainValue(for: keyAccount)
        PatchBundleKeyStore.clear()
        isActive = false
        expirationDate = nil
        lastCheckedAt = nil
        messageKey = nil
        maskedKey = nil
        isOffline = false
    }

    private func validate(key: String, persistOnSuccess: Bool) {
        isActive = false
        guard let endpoint else {
            isActive = false
            messageKey = "license.error_configuration"
            return
        }

        isBusy = true
        isOffline = false
        messageKey = "license.checking"

        Task {
            defer { isBusy = false }
            do {
                let response = try await sendValidation(key: key, endpoint: endpoint)
                let active = response.valid
                    && response.outcome.lowercased() == "active"
                    && (response.expiresAt == nil || response.expiresAt! > Date())

                expirationDate = response.expiresAt
                lastCheckedAt = Date()
                isOffline = false
                guard active else {
                    PatchBundleKeyStore.clear()
                    isActive = false
                    messageKey = Self.messageKey(for: response.outcome)
                    return
                }

                if persistOnSuccess {
                    do {
                        try saveKeychainString(key, for: keyAccount)
                    } catch {
                        isActive = false
                        messageKey = "license.error_secure_storage"
                        return
                    }
                }

                // An active answer is not enough: the server must prove it came
                // from us. The session is Ed25519-signed with a key whose public
                // half is pinned below, so a repointed endpoint cannot mint one.
                let identifier = try deviceID()
                guard let token = response.session,
                      SessionVerifier.claims(in: token, deviceID: identifier, project: projectID) != nil else {
                    PatchBundleKeyStore.clear()
                    isActive = false
                    messageKey = "license.error_server"
                    return
                }
                // The feed encrypts its shared wrapping key to this installation's
                // Secure Enclave key. The unwrapped value is memory-only; it is
                // still recoverable by an attacker controlling a live process.
                do {
                    try await PatchBundleKeyStore.refresh(
                        licenseKey: key,
                        deviceID: identifier
                    )
                } catch PatchBundleKeyError.unauthorized {
                    PatchBundleKeyStore.clear()
                    log("patches: bundle key exchange rejected")
                } catch {
                    log("patches: bundle key unavailable — \(error)")
                }
                isActive = true
                messageKey = nil
                maskedKey = Self.mask(key)
            } catch LicenseRequestError.network {
                isActive = false
                isOffline = true
                messageKey = "license.error_offline"
            } catch LicenseRequestError.secureStorage {
                isActive = false
                messageKey = "license.error_secure_storage"
            } catch {
                isActive = false
                isOffline = false
                messageKey = "license.error_server"
            }
        }
    }

    private func sendValidation(key: String, endpoint: URL) async throws -> ValidationResponse {
        let body: [String: String] = [
            "key": key,
            "deviceId": try deviceID(),
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "projectId": projectID
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseRequestError.network
        }
        guard let response = urlResponse as? HTTPURLResponse else {
            throw LicenseRequestError.network
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LicenseRequestError.server
        }
        do {
            return try JSONDecoder().decode(ValidationResponse.self, from: data)
        } catch {
            throw LicenseRequestError.server
        }
    }

    private func deviceID() throws -> String {
        if let existing = keychainString(for: deviceAccount), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        try saveKeychainString(value, for: deviceAccount)
        return value
    }

    private func keychainString(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func saveKeychainString(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw LicenseRequestError.secureStorage
        }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw LicenseRequestError.secureStorage
        }
    }

    private func deleteKeychainValue(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    private static func mask(_ key: String) -> String {
        "••••-\(key.suffix(4))"
    }

    private static func messageKey(for outcome: String) -> String {
        switch outcome.lowercased() {
        case "invalid", "invalid_key", "not_found": return "license.error_invalid"
        case "expired": return "license.error_expired"
        case "revoked": return "license.error_revoked"
        case "frozen", "suspended": return "license.error_frozen"
        case "device_limit": return "license.error_device_limit"
        case "invalid_device": return "license.error_device"
        case "rate_limited": return "license.error_rate_limited"
        case "wrong_project": return "license.error_wrong_project"
        default: return "license.error_inactive"
        }
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
        let outcome: String
        let expiresAt: Date?
        let session: String?

        private enum CodingKeys: String, CodingKey {
            case valid
            case outcome
            case expiresAt
            case session
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            valid = try container.decode(Bool.self, forKey: .valid)
            outcome = try container.decode(String.self, forKey: .outcome)
            session = try container.decodeIfPresent(String.self, forKey: .session)
            guard let rawDate = try container.decodeIfPresent(String.self, forKey: .expiresAt) else {
                expiresAt = nil
                return
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let parsed = formatter.date(from: rawDate) ?? ISO8601DateFormatter().date(from: rawDate) else {
                throw DecodingError.dataCorruptedError(forKey: .expiresAt, in: container, debugDescription: "Invalid license expiration date")
            }
            expiresAt = parsed
        }
    }

    /// The signed claims the licence worker returns with an active answer.
    /// Only the fields this client acts on are decoded; the signature covers
    /// the whole payload, so unknown fields are still authenticated.
    private struct SessionClaims: Decodable {
        let v: Int
        let iss: String
        let aud: String
        let kid: String
        let project: String
        let keyId: Int
        let device: String
        let nonce: String
        let exp: Int
    }

    /// `base64url(claims).base64url(ed25519 signature)`.
    ///
    /// The public half is pinned here. Rotating the signing key requires a
    /// build, which is the point: a server an attacker controls cannot answer
    /// for this one.
    private enum SessionVerifier {
        private static let pinnedPublicKey = "R3pdNCNDvN23ofwX8d262L8kc446tjhhE0hayw8d7Fg="
        private static let issuer = "trystore-license"
        private static let audience = "trystore-feed"
        private static let keyID = "trystore-ed25519-v1"

        static func claims(in token: String, deviceID: String, project: String) -> SessionClaims? {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let payload = decode(String(parts[0])),
                  let signature = decode(String(parts[1])),
                  let rawKey = Data(base64Encoded: pinnedPublicKey),
                  rawKey.count == 32,
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
                  publicKey.isValidSignature(signature, for: Data(parts[0].utf8)),
                  let claims = try? JSONDecoder().decode(SessionClaims.self, from: payload) else {
                return nil
            }
            let now = Int(Date().timeIntervalSince1970)
            guard claims.v == 1,
                  claims.iss == issuer,
                  claims.aud == audience,
                  claims.kid == keyID,
                  claims.project == project,
                  claims.device.caseInsensitiveCompare(deviceID) == .orderedSame,
                  claims.nonce.count >= 16,
                  claims.exp > now else {
                return nil
            }
            return claims
        }

        private static func decode(_ text: String) -> Data? {
            var value = text
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while value.count % 4 != 0 { value.append("=") }
            return Data(base64Encoded: value)
        }
    }

    private enum LicenseRequestError: Error {
        case network
        case server
        case secureStorage
    }

}
