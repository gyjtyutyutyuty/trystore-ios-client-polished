import CryptoKit
import Foundation
import UIKit

/// Pulls the published patch manifest from the Cloudflare worker and installs
/// any package whose digest differs from the local copy. This is what lets the
/// patch list change without shipping a new IPA.
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
    }

    /// Worker origin. Swap per build flavor if the deployment moves.
    private let baseURL = URL(string: "https://trystore-patch-feed.burgoajustin.workers.dev")!
    private let lastCheckKey = "patchFeed.lastCheck"
    private let minimumInterval: TimeInterval = 60

    private var isSyncing = false
    private var didLaunchSync = false

    /// One forced manifest check per app process, then the normal throttle.
    /// This is what makes a Telegram upload land on the next launch without
    /// waiting for the 30-minute window.
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
            guard !manifest.patches.isEmpty else { return }

            var installed = 0
            var current = 0
            var skipped = 0
            var failed = 0

            for entry in manifest.patches {
                if Task.isCancelled { return }
                while store.isBusy {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    if Task.isCancelled { return }
                }
                guard store.passwordRequest == nil else { break }
                let entryStem = URL(fileURLWithPath: entry.file)
                    .deletingPathExtension()
                    .lastPathComponent
                let local = store.items.first(where: { item in
                    let localFile = item.packageURL.deletingPathExtension().lastPathComponent
                    let localName = item.project?.name ?? localFile
                    return Self.normalizedName(localFile) == Self.normalizedName(entryStem)
                        || Self.normalizedName(localName) == Self.normalizedName(entry.name)
                })
                if let local,
                   let localDigest = digest(of: local.packageURL),
                   localDigest == entry.sha256 {
                    current += 1
                    continue
                }
                switch await install(entry: entry, store: store) {
                case .installed: installed += 1
                case .skipped: skipped += 1
                case .failed: failed += 1
                }
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            store.noteFeedStatus(
                "FEED \(manifest.patches.count) | \(installed) updated | \(current) current | "
                + "\(skipped) skipped | \(failed) failed | \(clock.string(from: Date()))"
            )
            log("patchfeed: manifest \(manifest.updatedAt ?? "unknown") applied")
            report(manifest: manifest, installed: installed, current: current, skipped: skipped, failed: failed)
        } catch {
            store.noteFeedStatus("FEED offline | \(Self.shortError(error))")
            log("patchfeed: sync skipped - \(error)")
        }
    }

    private func fetchManifest(project: String) async throws -> Manifest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/patches/\(project)/manifest.json"))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.badResponse
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            throw FeedError.badManifest
        }
        return manifest
    }

    private func install(entry: Entry, store: PatchProjectStore) async -> FeedPackageResult {
        let remote = entry.url.hasPrefix("http")
            ? URL(string: entry.url)!
            : baseURL.appendingPathComponent(entry.url.hasPrefix("/") ? String(entry.url.dropFirst()) : entry.url)

        do {
            var request = URLRequest(url: remote)
            request.timeoutInterval = 60
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw FeedError.downloadFailed
            }

            guard let digest = digest(of: temporaryURL), digest == entry.sha256 else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw FeedError.downloadFailed
            }

            // One legacy or protected package must not abort the whole sync.
            // Schema-9 visual bundles are already inside the IPA; sending them
            // through the remote importer throws unsupportedVersion.
            guard let packageData = try? Data(contentsOf: temporaryURL, options: .mappedIfSafe),
                  let summary = try? PatchPackageCodec.inspect(packageData),
                  (1...PatchPackageCodec.latestSchemaVersion).contains(summary.schemaVersion),
                  !summary.isPasswordProtected else {
                try? FileManager.default.removeItem(at: temporaryURL)
                log("patchfeed: skipped incompatible package \(entry.file)")
                return .skipped
            }

            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("PatchFeed", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent(entry.file)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temporaryURL, to: target)

            let importError: String? = await withCheckedContinuation { continuation in
                store.importPackage(at: target, reportsSuccess: false) { error in
                    continuation.resume(returning: error)
                }
            }
            try? FileManager.default.removeItem(at: target)
            if let importError {
                log("patchfeed: import failed \(entry.file) - \(importError)")
                return .failed
            }
            log("patchfeed: imported \(entry.file) (\(entry.size) B)")
            return .installed
        } catch {
            log("patchfeed: failed \(entry.file) - \(error)")
            return .failed
        }
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
            case .importFailed: return "import failed"
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
                log("patchfeed: report failed - \(error)")
            }
        }
    }

    private func digest(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
