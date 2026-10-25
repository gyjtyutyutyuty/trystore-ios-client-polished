import Combine
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
    @Published private(set) var patchBundleKey: Data?

    private let keychainService = "com.trystore.license"
    private let keyAccount = "license-key"
    private let deviceAccount = "device-id"
    private let defaultEndpoint = "https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate"

    private var endpoint: URL? {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_LICENSE_API_URL") as? String
        let value = (configured?.isEmpty == false ? configured : defaultEndpoint) ?? defaultEndpoint
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private var projectID: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PROJECT_ID") as? String
        return configured?.isEmpty == false ? configured! : "trystore"
    }

    var hasSavedKey: Bool { keychainString(for: keyAccount) != nil }

    func beginLaunchSession() {
        guard !isBusy else { return }
        guard let key = keychainString(for: keyAccount), !key.isEmpty else {
            patchBundleKey = nil
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
            patchBundleKey = nil
            isActive = false
            messageKey = "license.error_required"
            return
        }
        isActive = false
        validate(key: key, persistOnSuccess: false)
    }

    func clear() {
        deleteKeychainValue(for: keyAccount)
        patchBundleKey = nil
        isActive = false
        expirationDate = nil
        lastCheckedAt = nil
        messageKey = nil
        maskedKey = nil
        isOffline = false
    }

    private func validate(key: String, persistOnSuccess: Bool) {
        patchBundleKey = nil
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
                    patchBundleKey = nil
                    isActive = false
                    messageKey = Self.messageKey(for: response.outcome)
                    return
                }

                let bundleKey: Data
                do {
                    bundleKey = try await sendPatchBundleKey(key: key, endpoint: endpoint)
                } catch {
                    patchBundleKey = nil
                    isActive = false
                    if let requestError = error as? LicenseRequestError,
                       case .network = requestError {
                        isOffline = true
                    } else {
                        isOffline = false
                    }
                    messageKey = isOffline ? "license.error_offline" : "license.error_server"
                    return
                }

                if persistOnSuccess {
                    do {
                        try saveKeychainString(key, for: keyAccount)
                    } catch {
                        patchBundleKey = nil
                        isActive = false
                        messageKey = "license.error_secure_storage"
                        return
                    }
                }
                patchBundleKey = bundleKey
                isActive = true
                messageKey = nil
                maskedKey = Self.mask(key)
            } catch LicenseRequestError.network {
                patchBundleKey = nil
                isActive = false
                isOffline = true
                messageKey = "license.error_offline"
            } catch LicenseRequestError.secureStorage {
                patchBundleKey = nil
                isActive = false
                messageKey = "license.error_secure_storage"
            } catch {
                patchBundleKey = nil
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

    private func sendPatchBundleKey(key: String, endpoint: URL) async throws -> Data {
        let keyEndpoint = endpoint.deletingLastPathComponent()
            .appendingPathComponent("patch-bundle-key")
        var request = URLRequest(url: keyEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "deviceId": try deviceID(),
            "projectId": projectID,
            "keyVersion": Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PATCH_BUNDLE_KEY_VERSION") as? String ?? "1"
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseRequestError.network
        }
        guard let response = response as? HTTPURLResponse else {
            throw LicenseRequestError.network
        }
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(PatchBundleKeyResponse.self, from: data),
              payload.valid,
              let bundleKey = Data(base64Encoded: payload.key),
              bundleKey.count == 32 else {
            throw LicenseRequestError.server
        }
        return bundleKey
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
        case "wrong_project": return "license.error_wrong_project"
        default: return "license.error_inactive"
        }
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
        let outcome: String
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey {
            case valid
            case outcome
            case expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            valid = try container.decode(Bool.self, forKey: .valid)
            outcome = try container.decode(String.self, forKey: .outcome)
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

    private enum LicenseRequestError: Error {
        case network
        case server
        case secureStorage
    }

    private struct PatchBundleKeyResponse: Decodable {
        let valid: Bool
        let key: String
    }
}
