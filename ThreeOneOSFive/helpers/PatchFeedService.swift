import CryptoKit
import Foundation
import UIKit

/// Pulls the published patch manifest from the Cloudflare worker and installs
/// any package whose digest differs from the local copy. Patch payloads remain
/// remote-only; this service never reads package bytes from the app bundle.
@MainActor
final class PatchFeedService {
    static let shared = PatchFeedService()

    struct Entry: Decodable {
        let file: String
        let name: String
        let sha256: String
        let size: Int
        let version: String
        let url: String
    }

    struct Manifest: Decodable {
        let schemaVersion: Int?
        let project: String
        let updatedAt: String?
        let patches: [Entry]
    }

    enum FeedError: Error {
        case badResponse
        case badManifest
        case downloadFailed
        case importFailed(String)
        case incompatiblePackage
        case identityMismatch(String)
        case cancelled
    }

    /// Worker origin. Swap per build flavor if the deployment moves.
    private let baseURL = URL(string: "https://trystore-patch-feed.burgoajustin.workers.dev")!
    private let lastCheckKey = "patchFeed.lastCheck"
    private let minimumInterval: TimeInterval = 60

    private var isSyncing = false
    private var didLaunchSync = false

    /// One forced manifest check per app process, then the normal throttle.
    /// This is what makes a Telegram upload land on the next launch without
    /// waiting for the normal refresh interval.
    func syncOnLaunch(store: PatchProjectStore) async {
        guard !didLaunchSync else {
            await syncIfDue(store: store)
            return
        }
        didLaunchSync = true
        await sync(store: store)
    }

    func syncIfDue(store: PatchProjectStore, force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard force || now - last >= minimumInterval else { return }
        await sync(store: store)
    }

    func sync(store: PatchProjectStore) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let manifest = try await fetchManifest(project: "trystore")
            var installed = 0
            var current = 0
            var skipped = 0
            var failed = 0
            var interrupted = false

            for entry in manifest.patches {
                if Task.isCancelled { return }
                do {
                    while store.isBusy {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        if Task.isCancelled { return }
                    }
                    guard store.passwordRequest == nil else {
                        interrupted = true
                        break
                    }

                    if let sourceDigest = UserDefaults.standard.string(forKey: importedDigestKey(for: entry)),
                       sourceDigest.caseInsensitiveCompare(entry.sha256) == .orderedSame,
                       let packageIDString = UserDefaults.standard.string(forKey: importedPackageIDKey(for: entry)),
                       let packageID = UUID(uuidString: packageIDString),
                       store.items.contains(where: { $0.id == packageID }) {
                        current += 1
                        continue
                    }

                    let entryStem = URL(fileURLWithPath: entry.file)
                        .deletingPathExtension()
                        .lastPathComponent
                    let fileMatches = store.items.filter { item in
                        let localFile = item.packageURL.deletingPathExtension().lastPathComponent
                        return Self.normalizedName(localFile) == Self.normalizedName(entryStem)
                    }
                    let nameMatches = store.items.filter { item in
                        guard let localName = item.project?.name else { return false }
                        return PatchProjectLibrary.projectNameMatches(
                            expected: entry.name,
                            actual: localName
                        )
                    }
                    let localCandidates = !fileMatches.isEmpty
                        ? fileMatches
                        : (nameMatches.count == 1 ? nameMatches : [])
                    let hasCurrentLocalCopy = localCandidates.contains { item in
                        guard let localDigest = digest(of: item.packageURL) else { return false }
                        return localDigest.caseInsensitiveCompare(entry.sha256) == .orderedSame
                    }
                    if hasCurrentLocalCopy {
                        current += 1
                        continue
                    }

                    try await install(entry: entry, store: store)
                    installed += 1
                } catch {
                    if Task.isCancelled { return }
                    if let feedError = error as? FeedError, case .cancelled = feedError { return }
                    if let feedError = error as? FeedError {
                        switch feedError {
                        case .incompatiblePackage, .identityMismatch(_):
                            skipped += 1
                        default:
                            failed += 1
                        }
                    } else {
                        failed += 1
                    }
                    log("patchfeed: \(entry.file) skipped — \(error)")
                }
            }

            if failed == 0 && !interrupted && !Task.isCancelled {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            }

            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            let partial = interrupted ? " | partial" : ""
            store.noteFeedStatus(
                "FEED \(manifest.patches.count) | \(installed) updated | \(current) current | "
                    + "\(skipped) skipped | \(failed) failed\(partial) | \(clock.string(from: Date()))"
            )
            if failed == 0 && !interrupted {
                log("patchfeed: manifest \(manifest.updatedAt ?? "unknown") applied")
            } else {
                log("patchfeed: \(failed) package(s) failed; will retry")
            }
            report(manifest: manifest, installed: installed, current: current, skipped: skipped, failed: failed)
        } catch {
            store.noteFeedStatus("FEED offline | \(Self.shortError(error))")
            log("patchfeed: sync skipped — \(error)")
        }
    }

    private func fetchManifest(project: String) async throws -> Manifest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/patches/\(project)/manifest.json"))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.badResponse
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            throw FeedError.badManifest
        }
        return manifest
    }

    private func install(entry: Entry, store: PatchProjectStore) async throws {
        guard !entry.file.isEmpty,
              entry.file != ".",
              entry.file != "..",
              URL(fileURLWithPath: entry.file).lastPathComponent == entry.file,
              !entry.file.contains("\\"),
              entry.file.lowercased().hasSuffix(".trystore"),
              !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.sha256.count == 64,
              entry.sha256.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              entry.size > 0,
              entry.size <= 25 * 1024 * 1024 else {
            throw FeedError.badManifest
        }

        let remote: URL
        if entry.url.hasPrefix("http") {
            guard let absoluteURL = URL(string: entry.url) else { throw FeedError.badManifest }
            remote = absoluteURL
        } else {
            let path = entry.url.hasPrefix("/") ? String(entry.url.dropFirst()) : entry.url
            remote = baseURL.appendingPathComponent(path)
        }
        guard remote.scheme?.lowercased() == "https",
              remote.host?.lowercased() == baseURL.host?.lowercased() else {
            throw FeedError.badManifest
        }

        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard !Task.isCancelled else { throw FeedError.cancelled }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.downloadFailed
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let downloadedSize = (attributes?[.size] as? NSNumber)?.intValue
        guard downloadedSize == entry.size,
              let downloadedDigest = digest(of: temporaryURL),
              downloadedDigest.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
            throw FeedError.downloadFailed
        }

        let packageData = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        let originalProjectName: String
        do {
            let originalSummary = try PatchPackageCodec.inspect(packageData)
            guard (1...PatchPackageCodec.latestSchemaVersion).contains(originalSummary.schemaVersion),
                  !originalSummary.isPasswordProtected,
                  let decoded = try? PatchPackageCodec.decode(packageData, password: nil) else {
                throw FeedError.incompatiblePackage
            }
            originalProjectName = decoded.project.name
        } catch PatchPackageError.unsupportedVersion {
            guard let legacy = try? PatchPackageCodec.decodeBundledResource(packageData),
                  legacy.summary.schemaVersion == 9,
                  !legacy.summary.isPasswordProtected else {
                throw FeedError.incompatiblePackage
            }
            originalProjectName = legacy.decoded.project.name
        } catch let feedError as FeedError {
            throw feedError
        } catch {
            throw FeedError.incompatiblePackage
        }

        guard PatchProjectLibrary.remoteFeedIdentityMatches(
            expectedManifestName: entry.name,
            fileName: entry.file,
            actualProjectName: originalProjectName
        ) else {
            throw FeedError.identityMismatch("\(entry.file): manifest \(entry.name), payload \(originalProjectName)")
        }

        let normalizedData: Data
        do {
            normalizedData = try PatchProjectLibrary.normalizeRemoteFeedPackage(packageData, fileName: entry.file)
        } catch {
            throw FeedError.incompatiblePackage
        }
        let didNormalize = normalizedData != packageData
        let importedSummary: PatchPackageSummary
        let importedProjectName: String
        do {
            importedSummary = try PatchPackageCodec.inspect(normalizedData)
            guard (1...PatchPackageCodec.latestSchemaVersion).contains(importedSummary.schemaVersion),
                  !importedSummary.isPasswordProtected,
                  let decoded = try? PatchPackageCodec.decode(normalizedData, password: nil) else {
                throw FeedError.incompatiblePackage
            }
            importedProjectName = decoded.project.name
        } catch let feedError as FeedError {
            throw feedError
        } catch {
            throw FeedError.incompatiblePackage
        }
        guard PatchProjectLibrary.remoteFeedIdentityMatches(
            expectedManifestName: entry.name,
            fileName: entry.file,
            actualProjectName: importedProjectName
        ) else {
            throw FeedError.identityMismatch("\(entry.file): normalized payload \(importedProjectName) does not match \(entry.name)")
        }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchFeed", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let stagedURL = stagingDirectory.appendingPathComponent(entry.file)
        try? FileManager.default.removeItem(at: stagedURL)
        try normalizedData.write(to: stagedURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: stagedURL) }

        let importError: String? = await withCheckedContinuation { continuation in
            store.importPackage(at: stagedURL, reportsSuccess: false) { error in
                continuation.resume(returning: error)
            }
        }
        if let importError {
            throw FeedError.importFailed(importError)
        }
        UserDefaults.standard.set(entry.sha256.lowercased(), forKey: importedDigestKey(for: entry))
        UserDefaults.standard.set(importedSummary.packageID.uuidString, forKey: importedPackageIDKey(for: entry))
        if didNormalize {
            log("patchfeed: normalized legacy package \(entry.file) to current schema")
        }
        log("patchfeed: imported \(entry.file) (\(entry.size) B)")
    }

    private func importedDigestKey(for entry: Entry) -> String {
        "patchFeed.imported.sha256.\(entry.file)"
    }

    private func importedPackageIDKey(for entry: Entry) -> String {
        "patchFeed.imported.packageID.\(entry.file)"
    }

    private static func normalizedName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func shortError(_ error: Error) -> String {
        if let feedError = error as? FeedError {
            switch feedError {
            case .badResponse: return "HTTP error"
            case .badManifest: return "bad manifest"
            case .downloadFailed: return "download failed"
            case .importFailed(_): return "import failed"
            case .incompatiblePackage: return "incompatible package"
            case .identityMismatch(_): return "identity mismatch"
            case .cancelled: return "cancelled"
            }
        }
        return "no connection"
    }

    private func report(
        manifest: Manifest,
        installed: Int,
        current: Int,
        skipped: Int,
        failed: Int
    ) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/patches/trystore/report"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "device": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "manifest": manifest.updatedAt ?? "",
            "total": manifest.patches.count,
            "installed": installed,
            "current": current,
            "skipped": skipped,
            "failed": failed,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                log("patchfeed: report failed — \(error)")
            }
        }
    }

    private func digest(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
