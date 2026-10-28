import CryptoKit
import Foundation

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

            for entry in manifest.patches {
                if Task.isCancelled { return }
                guard let local = store.items.first(where: {
                    $0.packageURL.lastPathComponent.caseInsensitiveCompare(entry.file) == .orderedSame
                }) else {
                    try await install(entry: entry, store: store)
                    continue
                }
                if local.summary.packageID.uuidString.isEmpty {
                    continue
                }
                if let localDigest = digest(of: local.packageURL), localDigest == entry.sha256 {
                    continue
                }
                try await install(entry: entry, store: store)
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            log("patchfeed: manifest \(manifest.updatedAt ?? "unknown") applied")
        } catch {
            log("patchfeed: sync skipped — \(error)")
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

    private func install(entry: Entry, store: PatchProjectStore) async throws {
        let remote = entry.url.hasPrefix("http")
            ? URL(string: entry.url)!
            : baseURL.appendingPathComponent(entry.url.hasPrefix("/") ? String(entry.url.dropFirst()) : entry.url)

        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.downloadFailed
        }

        guard let digest = digest(of: temporaryURL), digest == entry.sha256 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw FeedError.downloadFailed
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchFeed", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = destination.appendingPathComponent(entry.file)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporaryURL, to: target)

        store.importPackage(at: target)
        log("patchfeed: queued \(entry.file) (\(entry.size) B)")
    }

    private func digest(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
