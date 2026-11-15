import CryptoKit
import Foundation

struct PatchFeedCredentials: Sendable {
    let licenseKey: String
    let deviceID: String
}

enum PatchFeedError: Error {
    case configuration
    case unauthorized
    case unavailable
    case invalidManifest
    case invalidPackage(String)
}

enum PatchResourceBundle {
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"
    private static let maximumPackageSize = 8 * 1024 * 1024

    private struct Manifest: Decodable {
        let project: String
        let patches: [Entry]
    }

    private struct Entry: Decodable {
        let file: String
        let name: String
        let url: URL
        let sha256: String
        let size: Int
    }

    static func load(
        credentials: PatchFeedCredentials,
        expected: [BundledPatch]
    ) async throws -> [String: Data] {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PATCH_FEED_URL") as? String,
              let baseURL = URL(string: configured),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host?.lowercased() == expectedHost,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil else {
            throw PatchFeedError.configuration
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let manifestURL = baseURL.appendingPathComponent("api/patches/trystore/manifest.json")
        var manifestData: Data?
        var lastManifestError: Error = PatchFeedError.unavailable
        for attempt in 0..<3 {
            do {
                let (data, manifestResponse) = try await session.data(
                    for: authenticatedRequest(url: manifestURL, credentials: credentials)
                )
                guard let manifestHTTP = manifestResponse as? HTTPURLResponse,
                      manifestHTTP.statusCode == 200,
                      manifestHTTP.url?.host?.lowercased() == expectedHost else {
                    throw PatchFeedError.unavailable
                }
                manifestData = data
                break
            } catch {
                lastManifestError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                }
            }
        }
        guard let manifestData else { throw lastManifestError }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        } catch {
            throw PatchFeedError.invalidManifest
        }
        guard manifest.project == "trystore" else {
            throw PatchFeedError.invalidManifest
        }

        var resources: [String: Data] = [:]
        resources.reserveCapacity(expected.count)
        for patch in expected {
            let matches = manifest.patches.filter {
                $0.file.caseInsensitiveCompare(patch.resourceName) == .orderedSame
            }
            guard matches.count == 1, let entry = matches.first,
                  entry.size > 0, entry.size <= maximumPackageSize,
                  entry.sha256.count == 64,
                  entry.sha256.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
                  isTrustedPackageURL(entry.url, filename: patch.resourceName, digest: entry.sha256) else {
                throw PatchFeedError.invalidManifest
            }
            // A dropped connection or a truncated body used to abort the whole
            // sync with one package missing. Retry the transfer and re-verify
            // the digest on every attempt before giving up on it.
            var fetched: Data?
            var lastError: Error = PatchFeedError.unavailable
            for attempt in 0..<3 {
                do {
                    let (data, response) = try await session.data(
                        for: authenticatedRequest(url: entry.url, credentials: credentials)
                    )
                    guard let http = response as? HTTPURLResponse,
                          http.statusCode == 200,
                          http.url?.host?.lowercased() == expectedHost,
                          data.count == entry.size,
                          data.count <= maximumPackageSize else {
                        throw PatchFeedError.unavailable
                    }
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard digest.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
                        throw PatchFeedError.invalidPackage(patch.resourceName)
                    }
                    fetched = data
                    break
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                    }
                }
            }
            guard let data = fetched else { throw lastError }
            resources[patch.resourceName] = data
        }
        return resources
    }

    private static func authenticatedRequest(
        url: URL,
        credentials: PatchFeedCredentials
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentials.licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/octet-stream, application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func isTrustedPackageURL(_ url: URL, filename: String, digest: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == expectedHost,
              components.user == nil, components.password == nil,
              components.path.hasPrefix("/patches/trystore/"),
              components.path.hasSuffix("/\(filename)"),
              components.queryItems?.count == 1,
              components.queryItems?.first?.name == "v",
              components.queryItems?.first?.value?.caseInsensitiveCompare(digest) == .orderedSame else {
            return false
        }
        return true
    }
}
