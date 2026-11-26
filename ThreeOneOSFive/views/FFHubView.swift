import SwiftUI
import Foundation
import UIKit

// MARK: - Wire models

struct FFHubSession: Decodable, Equatable {
    let role: String
    let activeSessions: Int?

    var isAdmin: Bool { role == "admin" }

    private enum CodingKeys: String, CodingKey {
        case role
        case activeSessions = "active_sessions"
    }
}

struct FFHubClothing: Decodable, Identifiable, Hashable {
    let itemID: String
    let type: String
    let label: String
    let inCatalog: Bool
    let thumbnailPath: String

    var id: String { itemID }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case type
        case label
        case inCatalog = "in_catalog"
        case thumbnailPath = "thumbnail_url"
    }
}

struct FFHubProfile: Decodable, Equatable {
    let uid: String
    let nickname: String
    let region: String
    let requestedRegion: String
    let avatarID: String
    let avatarInCatalog: Bool
    let clothes: [FFHubClothing]
    let clothesState: String
    let catalogVersion: String

    private enum CodingKeys: String, CodingKey {
        case uid
        case nickname
        case region
        case requestedRegion = "requested_region"
        case avatarID = "avatar_id"
        case avatarInCatalog = "avatar_in_catalog"
        case clothes
        case clothesState = "clothes_state"
        case catalogVersion = "catalog_version"
    }
}

struct FFHubJob: Decodable, Equatable {
    let id: String
    let state: String
    let detail: String?
    let progress: Double?
    let downloadURL: String?
    let mounted: [String]?
    let missing: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case state
        case detail
        case progress
        case downloadURL = "download_url"
        case mounted
        case missing
    }
}

private struct FFHubJobEnvelope: Decodable {
    let job: FFHubJob
}

private struct FFHubRevokeResponse: Decodable {
    let revoked: Int
}

private struct FFHubErrorEnvelope: Decodable {
    let detail: FFHubErrorDetail?
    let error: String?
}

private struct FFHubErrorDetail: Decodable {
    let error: String?
}

enum FFHubRegion: String, CaseIterable, Identifiable {
    case us
    case br
    case na
    case latam
    case sg
    case id
    case th
    case vn
    case my

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum FFHubError: Error, Equatable {
    case invalidPassword
    case unauthorized
    case noSession
    case adminRequired
    case invalidUID
    case invalidRegion
    case profileNotFound
    case clothesUnavailable
    case clothesEmpty
    case avatarNotInCatalog
    case providerRateLimited
    case providerAuth
    case providerNotConfigured
    case rateLimited
    case sessionStoreUnavailable
    case forbiddenOrigin
    case network
    case server(String)

    var messageKey: String {
        switch self {
        case .invalidPassword: return "ffhub.error.invalid_password"
        case .unauthorized, .noSession: return "ffhub.error.session_required"
        case .adminRequired: return "ffhub.error.admin_required"
        case .invalidUID: return "ffhub.error.invalid_uid"
        case .invalidRegion: return "ffhub.error.invalid_region"
        case .profileNotFound: return "ffhub.error.profile_not_found"
        case .clothesUnavailable: return "ffhub.error.clothes_unavailable"
        case .clothesEmpty: return "ffhub.error.clothes_empty"
        case .avatarNotInCatalog: return "ffhub.error.avatar_not_in_catalog"
        case .providerRateLimited: return "ffhub.error.provider_rate_limited"
        case .providerAuth: return "ffhub.error.provider_auth"
        case .providerNotConfigured: return "ffhub.error.provider_not_configured"
        case .rateLimited: return "ffhub.error.rate_limited"
        case .sessionStoreUnavailable: return "ffhub.error.session_store_unavailable"
        case .forbiddenOrigin: return "ffhub.error.origin"
        case .network: return "ffhub.error.network"
        case .server: return "ffhub.error.server"
        }
    }
}

// MARK: - Panel client

/// The panel sets its session cookie on a 303 login response. Following that
/// redirect would hide the Set-Cookie header from the caller, so the session
/// deliberately stops at the redirect instead of loading the panel HTML.
private final class FFHubNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor FFHubClient {
    static let shared = FFHubClient()

    private let baseURL = URL(string: "https://ffhub-outfit-panel-nzvoam.freebuff.site")!
    private let session: URLSession
    private var cookie: String?
    private var imageCache: [String: Data] = [:]

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        session = URLSession(
            configuration: configuration,
            delegate: FFHubNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func loginAdmin(password: String) async throws -> FFHubSession {
        cookie = nil
        imageCache.removeAll()
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let body = Self.formBody(["admin": trimmed]) else {
            throw FFHubError.invalidPassword
        }

        let request = makeRequest(
            path: "/api/session",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            authenticated: false
        )
        let (data, response) = try await raw(request)

        switch response.statusCode {
        case 200..<400:
            guard cookie != nil else { throw FFHubError.sessionStoreUnavailable }
            return try await sessionInfo()
        case 401:
            throw FFHubError.invalidPassword
        case 429:
            throw FFHubError.rateLimited
        case 503:
            throw FFHubError.sessionStoreUnavailable
        default:
            throw Self.mapError(status: response.statusCode, code: Self.errorCode(from: data))
        }
    }

    func sessionInfo() async throws -> FFHubSession {
        guard cookie != nil else { throw FFHubError.noSession }
        let data = try await perform(makeRequest(path: "/api/session", method: "GET"))
        return try decode(FFHubSession.self, from: data)
    }

    func logout() async throws {
        guard cookie != nil else { return }
        let (data, response) = try await raw(makeRequest(path: "/api/session", method: "DELETE"))
        switch response.statusCode {
        case 200, 204, 401:
            cookie = nil
            imageCache.removeAll()
        default:
            throw Self.mapError(status: response.statusCode, code: Self.errorCode(from: data))
        }
    }

    func revoke() async throws -> Int {
        let body = Data("{}".utf8)
        let request = makeRequest(
            path: "/api/session/revoke",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        let data = try await perform(request)
        return try decode(FFHubRevokeResponse.self, from: data).revoked
    }

    func profile(uid: String, region: String) async throws -> FFHubProfile {
        let body = try JSONSerialization.data(withJSONObject: ["uid": uid, "region": region])
        let request = makeRequest(
            path: "/api/profile",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        let data = try await perform(request)
        return try decode(FFHubProfile.self, from: data)
    }

    func generate(profile: FFHubProfile) async throws -> FFHubJob {
        let payload: [String: Any] = [
            "uid": profile.uid,
            "region": profile.requestedRegion,
            "avatar_id": profile.avatarID,
            "items": profile.clothes.map { $0.itemID }
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = makeRequest(
            path: "/api/jobs",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        let data = try await perform(request)
        var job = try decode(FFHubJobEnvelope.self, from: data).job

        if job.state == "queued" || job.state == "generating" {
            job = try await waitForJob(id: job.id)
        }
        return job
    }

    func download(job: FFHubJob) async throws -> URL {
        guard let reference = job.downloadURL else {
            throw FFHubError.server("missing_download")
        }

        let path: String
        if reference.hasPrefix("http") || reference.hasPrefix("/api") {
            path = reference
        } else {
            path = "/api" + reference
        }

        let data = try await perform(makeRequest(path: path, method: "GET"))
        let safeID = job.id.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFHub-\(safeID).glb")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func thumbnailData(itemID: String) async throws -> Data {
        if let cached = imageCache[itemID] { return cached }
        let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemID
        let data = try await perform(makeRequest(path: "/api/thumbnail/\(encoded)", method: "GET"))
        imageCache[itemID] = data
        return data
    }

    private func waitForJob(id: String) async throws -> FFHubJob {
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let data = try await perform(makeRequest(path: "/api/jobs/\(id)", method: "GET"))
            let job = try decode(FFHubJobEnvelope.self, from: data).job
            if job.state != "queued" && job.state != "generating" {
                return job
            }
        }
        throw FFHubError.server("job_timeout")
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        authenticated: Bool = true
    ) -> URLRequest {
        let url = URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 120
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if method != "GET" {
            request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        }
        if authenticated, let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func raw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FFHubError.network
            }
            captureCookie(from: http)
            return (data, http)
        } catch let error as FFHubError {
            throw error
        } catch {
            throw FFHubError.network
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await raw(request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                cookie = nil
                imageCache.removeAll()
            }
            throw Self.mapError(status: response.statusCode, code: Self.errorCode(from: data))
        }
        return data
    }

    private func captureCookie(from response: HTTPURLResponse) {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie"),
              let start = header.range(of: "ffhub_session=") else {
            return
        }

        if header.lowercased().contains("max-age=0") {
            cookie = nil
            return
        }

        let tail = header[start.lowerBound...]
        let pair = tail
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
        if let pair, !pair.isEmpty {
            cookie = String(pair)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FFHubError.server("decode")
        }
    }

    private static func formBody(_ fields: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func errorCode(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(FFHubErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.detail?.error ?? envelope.error
    }

    private static func mapError(status: Int, code: String?) -> FFHubError {
        switch code {
        case "invalid_uid": return .invalidUID
        case "invalid_region": return .invalidRegion
        case "profile_not_found": return .profileNotFound
        case "clothes_unavailable": return .clothesUnavailable
        case "clothes_empty": return .clothesEmpty
        case "avatar_not_in_catalog": return .avatarNotInCatalog
        case "provider_rate_limited": return .providerRateLimited
        case "provider_auth": return .providerAuth
        case "provider_not_configured": return .providerNotConfigured
        case "rate_limited": return .rateLimited
        case "session_required": return .noSession
        case "admin_required": return .adminRequired
        case "session_store_unavailable": return .sessionStoreUnavailable
        case "forbidden_origin": return .forbiddenOrigin
        default:
            if status == 401 { return .unauthorized }
            if status == 403 { return .adminRequired }
            if status == 429 { return .rateLimited }
            if status == 503 { return .sessionStoreUnavailable }
            return .server(code ?? "http_\(status)")
        }
    }
}

// MARK: - Screen model

@MainActor
final class FFHubControlModel: ObservableObject {
    @Published var session: FFHubSession?
    @Published var adminPassword = ""
    @Published var isSigningIn = false
    @Published var isRefreshing = false
    @Published var isSigningOut = false
    @Published var isRevoking = false
    @Published var isRevokeConfirmationPresented = false
    @Published var sessionErrorKey: String?
    @Published var noticeKey: String?
    @Published var noticeCount = 0

    @Published var uid = ""
    @Published var region = FFHubRegion.us.rawValue
    @Published var profile: FFHubProfile?
    @Published var isLookingUp = false
    @Published var isGenerating = false
    @Published var job: FFHubJob?
    @Published var isDownloading = false
    @Published var downloadedURL: URL?
    @Published var exportErrorKey: String?

    private let client = FFHubClient.shared

    var canLookup: Bool {
        session != nil
            && !isLookingUp
            && !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerate: Bool {
        session != nil
            && !isGenerating
            && profile?.clothesState == "available"
            && profile?.avatarInCatalog == true
    }

    func restore() async {
        guard session == nil else { return }
        do {
            session = try await client.sessionInfo()
        } catch {
            // No cookie or an expired one: the sign-in form is the right state.
        }
    }

    func signIn() async {
        guard !isSigningIn else { return }
        let password = adminPassword
        guard !password.isEmpty else {
            sessionErrorKey = "ffhub.error.invalid_password"
            return
        }

        isSigningIn = true
        sessionErrorKey = nil
        noticeKey = nil
        do {
            session = try await client.loginAdmin(password: password)
            adminPassword = ""
        } catch {
            sessionErrorKey = message(for: error)
        }
        isSigningIn = false
    }

    func refreshSession() async {
        guard session != nil, !isRefreshing else { return }
        isRefreshing = true
        sessionErrorKey = nil
        do {
            session = try await client.sessionInfo()
        } catch {
            sessionErrorKey = message(for: error)
        }
        isRefreshing = false
    }

    func logout() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        sessionErrorKey = nil
        do {
            try await client.logout()
            session = nil
            resetExport()
            noticeKey = nil
        } catch {
            sessionErrorKey = message(for: error)
        }
        isSigningOut = false
    }

    func revoke() async {
        guard !isRevoking else { return }
        isRevoking = true
        sessionErrorKey = nil
        noticeKey = nil
        do {
            let count = try await client.revoke()
            noticeCount = count
            if count == 0 {
                noticeKey = "ffhub.session.revoked_none"
            } else if count == 1 {
                noticeKey = "ffhub.session.revoked_one"
            } else {
                noticeKey = "ffhub.session.revoked_many"
            }
            if let refreshed = try? await client.sessionInfo() {
                session = refreshed
            }
        } catch {
            sessionErrorKey = message(for: error)
        }
        isRevoking = false
    }

    func lookup() async {
        guard session != nil, !isLookingUp else { return }
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (5...15).contains(trimmed.count), trimmed.allSatisfy({ $0.isNumber }) else {
            exportErrorKey = "ffhub.error.invalid_uid"
            return
        }

        isLookingUp = true
        exportErrorKey = nil
        profile = nil
        job = nil
        downloadedURL = nil
        do {
            profile = try await client.profile(uid: trimmed, region: region)
            uid = trimmed
        } catch {
            exportErrorKey = message(for: error)
        }
        isLookingUp = false
    }

    func generate() async {
        guard let profile, canGenerate else { return }
        isGenerating = true
        exportErrorKey = nil
        job = nil
        downloadedURL = nil
        do {
            job = try await client.generate(profile: profile)
        } catch {
            exportErrorKey = message(for: error)
        }
        isGenerating = false
    }

    func download() async {
        guard let job, !isDownloading else { return }
        isDownloading = true
        exportErrorKey = nil
        do {
            downloadedURL = try await client.download(job: job)
        } catch {
            exportErrorKey = message(for: error)
        }
        isDownloading = false
    }

    private func message(for error: Error) -> String {
        guard let hub = error as? FFHubError else {
            return "ffhub.error.server"
        }
        if hub == .unauthorized || hub == .noSession {
            session = nil
        }
        return hub.messageKey
    }

    private func resetExport() {
        profile = nil
        job = nil
        downloadedURL = nil
        isLookingUp = false
        isGenerating = false
        isDownloading = false
        exportErrorKey = nil
    }
}

// MARK: - Screen

struct FFHubControlView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = FFHubControlModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        header
                        sessionPanel
                        exportPanel
                        demoPanel
                    }
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationTitle(language.text("ffhub.section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) {
                        AppHaptics.tap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(AppTheme.accent)
        }
        .presentationDetents([.large])
        .task { await model.restore() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            AppLogo(size: 46)
                .padding(3)
                .background(
                    AppPalette.raised,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("ffhub.section"))
                    .font(AppType.section())
                    .tracking(1.2)
                    .foregroundStyle(AppPalette.textPrimary)

                Text(language.text("ffhub.subtitle"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let session = model.session {
                AppStatChip(
                    icon: session.isAdmin ? "lock.shield.fill" : "person.fill",
                    text: language.text(
                        session.isAdmin ? "ffhub.session.role_admin" : "ffhub.session.role_user"
                    )
                )
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(
                icon: "lock.shield",
                title: language.text("ffhub.session.title"),
                subtitle: language.text("ffhub.session.subtitle")
            )

            if let session = model.session {
                HStack(spacing: AppSpacing.s) {
                    AppStatChip(
                        icon: session.isAdmin ? "lock.shield.fill" : "person.fill",
                        text: language.text(
                            session.isAdmin ? "ffhub.session.role_admin" : "ffhub.session.role_user"
                        )
                    )
                    Spacer(minLength: AppSpacing.s)
                    refreshButton
                }

                if session.isAdmin, let count = session.activeSessions {
                    Text(activeText(count))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                secondaryButton(
                    title: language.text("ffhub.session.logout"),
                    icon: "rectangle.portrait.and.arrow.right"
                ) {
                    Task { await model.logout() }
                }
                .disabled(model.isSigningOut)

                if session.isAdmin {
                    revokeButton

                    if let noticeKey = model.noticeKey {
                        Text(
                            noticeKey == "ffhub.session.revoked_many"
                                ? language.text(noticeKey, model.noticeCount)
                                : language.text(noticeKey)
                        )
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                passwordField

                primaryButton(
                    title: language.text(
                        model.isSigningIn ? "ffhub.session.signing_in" : "ffhub.session.sign_in"
                    ),
                    icon: "lock.open",
                    enabled: !model.adminPassword.isEmpty && !model.isSigningIn
                ) {
                    Task { await model.signIn() }
                }

                Text(language.text("ffhub.session.password_hint"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let key = model.sessionErrorKey {
                errorLabel(key)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
        .confirmationDialog(
            language.text("ffhub.session.revoke_title"),
            isPresented: $model.isRevokeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(language.text("ffhub.session.revoke_action"), role: .destructive) {
                Task { await model.revoke() }
            }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("ffhub.session.revoke_message"))
        }
    }

    private var passwordField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "key.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.textTertiary)
                .accessibilityHidden(true)

            SecureField(language.text("ffhub.session.password"), text: $model.adminPassword)
                .font(AppType.body())
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await model.signIn() } }
                .accessibilityLabel(language.text("ffhub.session.password"))
        }
        .padding(.horizontal, AppSpacing.m)
        .frame(minHeight: 46)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
    }

    private var refreshButton: some View {
        Button {
            AppHaptics.tap()
            Task { await model.refreshSession() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppPalette.canvas, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing)
        .accessibilityLabel(language.text("ffhub.session.refresh"))
    }

    private var revokeButton: some View {
        Button {
            AppHaptics.tap()
            model.isRevokeConfirmationPresented = true
        } label: {
            Label(
                language.text(
                    model.isRevoking ? "ffhub.session.revoking" : "ffhub.session.revoke"
                ),
                systemImage: "person.badge.minus"
            )
            .font(AppType.label().weight(.semibold))
            .foregroundStyle(AppPalette.coral)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(AppPalette.coral.opacity(0.10), in: Capsule())
            .overlay(
                Capsule().strokeBorder(AppPalette.coral.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(model.isRevoking)
        .opacity(model.isRevoking ? 0.55 : 1)
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(
                icon: "cube.transparent",
                title: language.text("ffhub.export.title"),
                subtitle: language.text("ffhub.export.subtitle")
            )

            if model.session == nil {
                Label(language.text("ffhub.export.need_session"), systemImage: "lock.fill")
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            uidField

            HStack(spacing: AppSpacing.s) {
                regionMenu
                Spacer(minLength: 0)
            }

            primaryButton(
                title: language.text(
                    model.isLookingUp ? "ffhub.export.looking_up" : "ffhub.export.lookup"
                ),
                icon: "magnifyingglass",
                enabled: model.canLookup
            ) {
                Task { await model.lookup() }
            }

            if let profile = model.profile {
                profileSection(profile)
                clothesSection(profile)

                primaryButton(
                    title: language.text(
                        model.isGenerating ? "ffhub.export.generating" : "ffhub.export.generate"
                    ),
                    icon: "cube.transparent",
                    enabled: model.canGenerate
                ) {
                    Task { await model.generate() }
                }

                if model.isGenerating {
                    progressRow(language.text("ffhub.export.generating"))
                }

                if let job = model.job {
                    jobSection(job)
                }
            }

            if let key = model.exportErrorKey {
                errorLabel(key)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private var uidField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "number")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.textTertiary)
                .accessibilityHidden(true)

            TextField(language.text("ffhub.export.uid"), text: $model.uid)
                .font(AppType.body())
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await model.lookup() } }
                .accessibilityLabel(language.text("ffhub.export.uid"))

            if !model.uid.isEmpty {
                Button {
                    model.uid = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("common.clear"))
            }
        }
        .padding(.horizontal, AppSpacing.m)
        .frame(minHeight: 46)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
    }

    private var regionMenu: some View {
        Menu {
            ForEach(FFHubRegion.allCases) { option in
                Button(option.label) {
                    model.region = option.rawValue
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(FFHubRegion(rawValue: model.region)?.label ?? model.region.uppercased())
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(AppType.label())
            .foregroundStyle(AppPalette.textPrimary)
            .padding(.horizontal, AppSpacing.m)
            .frame(minHeight: 46)
            .background(AppPalette.raised, in: Capsule())
        }
        .accessibilityLabel(language.text("ffhub.export.region"))
    }

    private func profileSection(_ profile: FFHubProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(profile.nickname.isEmpty ? profile.uid : profile.nickname)
                .font(AppType.display())
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.s) {
                AppStatChip(icon: "number", text: profile.uid)
                AppStatChip(icon: "globe", text: profile.region.uppercased())
                AppStatChip(icon: "person.fill", text: profile.avatarID)
            }

            if !profile.avatarInCatalog {
                Label(
                    language.text("ffhub.export.avatar_missing"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(AppType.meta())
                .foregroundStyle(AppPalette.amber)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func clothesSection(_ profile: FFHubProfile) -> some View {
        if profile.clothesState == "available" {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack {
                    Text(language.text("ffhub.export.clothes_title"))
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textSecondary)
                    Spacer(minLength: AppSpacing.s)
                    Text(itemCountText(profile.clothes.count))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)],
                    spacing: AppSpacing.s
                ) {
                    ForEach(profile.clothes) { item in
                        clothesTile(item)
                    }
                }
            }
        } else if profile.clothesState == "empty" {
            stateNote(
                icon: "hanger",
                key: "ffhub.export.clothes_empty",
                tint: AppPalette.textTertiary
            )
        } else {
            stateNote(
                icon: "exclamationmark.triangle.fill",
                key: "ffhub.export.clothes_unavailable",
                tint: AppPalette.amber
            )
        }
    }

    private func clothesTile(_ item: FFHubClothing) -> some View {
        HStack(spacing: AppSpacing.s) {
            FFHubThumbnail(itemID: item.itemID)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.isEmpty ? item.itemID : item.label)
                    .font(AppType.body().weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)

                Text(language.text(item.inCatalog ? "ffhub.export.mesh" : "ffhub.export.no_model"))
                    .font(AppType.meta())
                    .foregroundStyle(item.inCatalog ? AppPalette.textTertiary : AppPalette.amber)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func jobSection(_ job: FFHubJob) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: job.state == "ready"
                    ? "checkmark.circle.fill"
                    : job.state == "partial"
                        ? "exclamationmark.triangle.fill"
                        : "xmark.octagon.fill")
                    .foregroundStyle(job.state == "ready"
                        ? AppTheme.accent
                        : job.state == "partial"
                            ? AppPalette.amber
                            : AppPalette.coral)

                Text(
                    job.state == "ready"
                        ? language.text("ffhub.export.ready")
                        : job.state == "partial"
                            ? language.text("ffhub.export.partial")
                            : language.text("ffhub.error.server")
                )
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if job.state == "ready" || job.state == "partial" {
                if let downloaded = model.downloadedURL {
                    FFHubWornOutfit(url: downloaded)

                    ShareLink(item: downloaded) {
                        Label(language.text("ffhub.export.share"), systemImage: "square.and.arrow.up")
                            .font(AppType.label().weight(.semibold))
                            .foregroundStyle(AppPalette.canvas)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(AppPressButtonStyle())

                    Text(language.text("ffhub.export.download_hint"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    primaryButton(
                        title: language.text(
                            model.isDownloading ? "ffhub.export.downloading" : "ffhub.export.download"
                        ),
                        icon: "arrow.down.circle",
                        enabled: !model.isDownloading
                    ) {
                        Task { await model.download() }
                    }

                    if model.isDownloading {
                        progressRow(language.text("ffhub.export.downloading"))
                    }
                }
            }
        }
    }

    private var demoPanel: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)

            Text(language.text("ffhub.export.demo_note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func primaryButton(
        title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(AppType.label().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(AppPalette.canvas)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func secondaryButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppType.label().weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppPalette.canvas, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(AppTheme.accent.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(AppPressButtonStyle())
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            ProgressView().tint(AppTheme.accent)
            Text(text)
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func stateNote(icon: String, key: String, tint: Color) -> some View {
        Label(language.text(key), systemImage: icon)
            .font(AppType.meta())
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorLabel(_ key: String) -> some View {
        Label(language.text(key), systemImage: "exclamationmark.triangle.fill")
            .font(AppType.meta())
            .foregroundStyle(AppPalette.amber)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func activeText(_ count: Int) -> String {
        switch count {
        case 0: return language.text("ffhub.session.active_zero")
        case 1: return language.text("ffhub.session.active_one")
        default: return language.text("ffhub.session.active_many", count)
        }
    }

    private func itemCountText(_ count: Int) -> String {
        count == 1
            ? language.text("ffhub.export.items_one")
            : language.text("ffhub.export.items_many", count)
    }
}

// MARK: - Downloaded outfit on the avatar

/// The downloaded export worn on the same SceneKit stage the wardrobe uses.
/// The GLB is a complete figure, so the stage swaps its bundled body for it
/// instead of hanging the pieces on the bundled character.
private struct FFHubWornOutfit: View {
    let url: URL

    @Environment(\.appLanguage) private var language
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)

                Text(language.text("ffhub.export.worn_title"))
                    .font(AppType.label().weight(.semibold))
                    .foregroundStyle(AppPalette.textSecondary)

                Spacer(minLength: 0)
            }

            CharacterStageView(
                model: .sakura,
                reduceMotion: reduceMotion,
                isActive: isVisible,
                outfit: WornOutfit(id: url.lastPathComponent, url: url)
            )
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.text("ffhub.export.worn_title"))
            .accessibilityHint(language.text("ffhub.export.worn_hint"))

            Text(language.text("ffhub.export.worn_note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - Authenticated thumbnail

private struct FFHubThumbnail: View {
    let itemID: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(AppPalette.raised)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else if failed {
                Image(systemName: "cube")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.textTertiary)
            } else {
                ProgressView().tint(AppTheme.accent)
            }
        }
        .task(id: itemID) {
            image = nil
            failed = false
            do {
                let data = try await FFHubClient.shared.thumbnailData(itemID: itemID)
                if let loaded = UIImage(data: data) {
                    image = loaded
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
        .accessibilityHidden(true)
    }
}
