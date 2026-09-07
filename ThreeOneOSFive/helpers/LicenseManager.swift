import Foundation
import Combine
import Security
import UIKit
import UserNotifications

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var isOffline = false
    @Published private(set) var requiresPatchRestore = false
    @Published var rememberKey = false

    private let service = "com.apple.mobile.MobileHouseArrest.license"
    private let tokenAccount = "license-token"
    private let expirationAccount = "license-expiration"
    private let deviceAccount = "device-id"
    private let rememberedKeyAccount = "remembered-key"
    private let rememberPreferenceAccount = "remember-key-preference"
    private let apiBaseURL = URL(string: "https://trystore-license-service.manus.space/api/v1/keys/validate")!

    init() {
        expirationDate = keychainString(for: expirationAccount).flatMap { Date(timeIntervalSince1970: TimeInterval($0) ?? 0) }
        isActive = expirationDate.map { $0 > Date() } ?? false
        rememberKey = keychainString(for: rememberPreferenceAccount) == "true"
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate <= Date()
    }

    var hasSavedLicenseToken: Bool {
        keychainString(for: tokenAccount) != nil
    }

    var maskedLicenseIdentifier: String {
        guard let token = keychainString(for: tokenAccount), token.count >= 4 else { return "Not available" }
        return "••••-\(token.suffix(4))"
    }

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0)
    }

    var statusText: String {
        guard isActive else { return expirationDate != nil ? "KEY EXPIRED" : "NO ACTIVE KEY" }
        guard let expirationDate else { return "KEY ACTIVE" }
        if expirationDate <= Date() { return "KEY EXPIRED" }
        if daysRemaining == 0 { return "EXPIRES TODAY" }
        return "\(daysRemaining) DAYS LEFT"
    }

    var remainingText: String {
        guard isActive else { return "Activation required" }
        guard let expirationDate else { return "KEY ACTIVE" }
        let totalSeconds = max(0, Int(expirationDate.timeIntervalSinceNow))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "RESTANTE: %02d días · %02d horas · %02d minutos · %02d segundos", days, hours, minutes, seconds)
    }

    var expirationText: String {
        guard let expirationDate else { return "No expiration recorded" }
        return "EXPIRA: \(expirationDate.formatted(date: .abbreviated, time: .shortened))"
    }

    func beginLaunchSession() {
        isActive = false
        isOffline = false
        message = rememberKey ? "ENTER KEY TO CONTINUE" : nil
        if !rememberKey {
            deleteKeychainValue(for: tokenAccount)
            deleteKeychainValue(for: expirationAccount)
            expirationDate = nil
        } else if hasSavedLicenseToken {
            refresh()
        }
    }

    func expireIfNeeded() {
        guard isActive, let expirationDate, expirationDate <= Date() else { return }
        isActive = false
        requiresPatchRestore = true
        message = "KEY EXPIRED"
    }

    func markPatchRestoreCompleted() {
        requiresPatchRestore = false
    }

    func refresh() {
        guard !isBusy else { return }
        guard let token = keychainString(for: tokenAccount) else {
            isActive = false
            message = "NO SAVED LICENSE"
            return
        }
        isBusy = true
        isOffline = false
        message = "CHECKING LICENSE…"
        Task {
            do {
                let response: ValidationResponse = try await request(
                    body: ["key": token, "deviceId": deviceID, "appVersion": appVersion]
                )
                if let expiresAt = response.expiresAt { try saveExpiration(expiresAt) } else { expirationDate = nil; deleteKeychainValue(for: expirationAccount) }
                isActive = response.valid && response.outcome == "active"
                requiresPatchRestore = !isActive
                lastCheckedAt = Date()
                isOffline = false
                message = isActive ? nil : "LICENSE IS NOT ACTIVE"
                isBusy = false
            } catch {
                isActive = false
                requiresPatchRestore = true
                isOffline = error is LicenseError && (error as? LicenseError) == .network
                message = userMessage(for: error)
                isBusy = false
            }
        }
    }

    func activate(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        isBusy = true
        isOffline = false
        message = "CONTACTING LICENSE SERVER…"
        Task {
            do {
                let response: ValidationResponse = try await request(
                    body: [
                        "key": trimmed,
                        "deviceId": deviceID,
                        "appVersion": appVersion
                    ]
                )
                guard response.valid && response.outcome == "active" else {
                    isActive = false
                    requiresPatchRestore = true
                    message = "KEY IS \(response.outcome.uppercased())"
                    isBusy = false
                    return
                }
                try saveString(trimmed, for: tokenAccount)
                if let expiresAt = response.expiresAt { try saveExpiration(expiresAt) } else { expirationDate = nil; deleteKeychainValue(for: expirationAccount) }
                try saveString(rememberKey ? "true" : "false", for: rememberPreferenceAccount)
                if rememberKey {
                    try saveString(trimmed, for: rememberedKeyAccount)
                } else {
                    deleteKeychainValue(for: rememberedKeyAccount)
                }
                isActive = response.valid && response.outcome == "active"
                requiresPatchRestore = !isActive
                lastCheckedAt = Date()
                isOffline = false
                message = isActive ? "KEY ACTIVATED" : "KEY EXPIRED"
                if isActive && (UserDefaults.standard.object(forKey: "trystore.activationConfirmations") as? Bool ?? true) {
                    sendActivationConfirmation()
                }
                isBusy = false
            } catch {
                isActive = false
                isOffline = error is LicenseError && (error as? LicenseError) == .network
                message = userMessage(for: error)
                isBusy = false
            }
        }
    }

    private func sendActivationConfirmation() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "TryStore License Active"
            content.body = "Your client license was activated successfully."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "trystore.activation.confirmation", content: content, trigger: nil)
            center.add(request)
        }
    }

    func rememberedKey() -> String? {
        keychainString(for: rememberedKeyAccount)
    }

    func forgetRememberedKey() {
        deleteKeychainValue(for: rememberedKeyAccount)
        try? saveString("false", for: rememberPreferenceAccount)
        rememberKey = false
    }

    func clear() {
        deleteKeychainValue(for: tokenAccount)
        deleteKeychainValue(for: expirationAccount)
        deleteKeychainValue(for: rememberedKeyAccount)
        deleteKeychainValue(for: rememberPreferenceAccount)
        expirationDate = nil
        isActive = false
        message = "KEY REMOVED"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var deviceID: String {
        if let stored = keychainString(for: deviceAccount), !stored.isEmpty { return stored }
        let value = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        try? saveString(value, for: deviceAccount)
        return value
    }

    private func saveExpiration(_ date: Date) throws {
        expirationDate = date
        try saveString(String(date.timeIntervalSince1970), for: expirationAccount)
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
        let outcome: String
        let expiresAt: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            valid = try container.decode(Bool.self, forKey: .valid)
            outcome = try container.decode(String.self, forKey: .outcome)
            if try container.decodeNil(forKey: .expiresAt) {
                expiresAt = nil
            } else if let date = try? container.decode(Date.self, forKey: .expiresAt) {
                expiresAt = date
            } else {
                let raw = try container.decode(String.self, forKey: .expiresAt)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                expiresAt = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
            }
        }

        private enum CodingKeys: String, CodingKey { case valid, outcome, expiresAt }
    }

    private struct APIError: Decodable { let error: String? }

    private func request<Response: Decodable>(body: [String: String]) async throws -> Response {
        let url = apiBaseURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Preserve a useful user-facing state for DNS, TLS, ATS, timeout, and offline failures.
            throw LicenseError.network
        }
        guard let http = response as? HTTPURLResponse else { throw LicenseError.network }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw LicenseError.server(apiError?.error ?? "license request failed")
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw LicenseError.server("Invalid license server response")
        }
    }

    private func userMessage(for error: Error) -> String {
        if let error = error as? LicenseError {
            switch error {
            case .server(let text): return text.uppercased()
            case .network: return "LICENSE SERVER UNAVAILABLE — CHECK CONNECTION AND RETRY"
            }
        }
        return "LICENSE REQUEST FAILED"
    }

    private enum LicenseError: Error, Equatable { case network; case server(String) }

    private func keychainString(for account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveString(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw LicenseError.network }
        } else if status != errSecSuccess {
            throw LicenseError.network
        }
    }

    private func deleteKeychainValue(for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
