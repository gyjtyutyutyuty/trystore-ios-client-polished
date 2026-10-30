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

            var failedEntries = 0
            for entry in manifest.patches {
                if Task.isCancelled { return }
                do {
                    while store.isBusy {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        if Task.isCancelled { return }
                    }
                    guard store.passwordRequest == nil else { return }
                    if let sourceDigest = UserDefaults.standard.string(forKey: importedDigestKey(for: entry)),
                       sourceDigest == entry.sha256,
                       let packageIDString = UserDefaults.standard.string(forKey: importedPackageIDKey(for: entry)),
                       let packageID = UUID(uuidString: packageIDString),
                       store.items.contains(where: { $0.id == packageID }) {
                        continue
                    }
                    let entryStem = URL(fileURLWithPath: entry.file).deletingPathExtension().lastPathComponent
                    let local = store.items.first(where: { item in
                        let localFile = item.packageURL.deletingPathExtension().lastPathComponent
                        let localName = item.project?.name ?? localFile
                        return Self.normalizedName(localFile) == Self.normalizedName(entryStem)
                            || Self.normalizedName(localName) == Self.normalizedName(entry.name)
                    })
                    if let local, digest(of: local.packageURL) == entry.sha256 {
                        continue
                    }
                    try await install(entry: entry, store: store)
                } catch {
                    failedEntries += 1
                    log("patchfeed: \(entry.file) skipped — \(error)")
                }
            }
            if failedEntries == 0 {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                log("patchfeed: manifest \(manifest.updatedAt ?? "unknown") applied")
            } else {
                log("patchfeed: \(failedEntries) package(s) failed; will retry")
            }
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
        guard !entry.file.isEmpty,
              entry.file != ".",
              entry.file != "..",
              URL(fileURLWithPath: entry.file).lastPathComponent == entry.file,
              !entry.file.contains("\\"),
              entry.file.lowercased().hasSuffix(".trystore"),
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
        guard remote.scheme == "https", remote.host == baseURL.host else {
            throw FeedError.badManifest
        }

        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.downloadFailed
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let downloadedSize = (attributes?[.size] as? NSNumber)?.intValue
        guard downloadedSize == entry.size,
              let digest = digest(of: temporaryURL), digest == entry.sha256 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw FeedError.downloadFailed
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchFeed", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = destination.appendingPathComponent(entry.file)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporaryURL, to: target)

        let downloadedData = try Data(contentsOf: target, options: .mappedIfSafe)
        let normalizedData = try PatchProjectLibrary.normalizeRemoteFeedPackage(downloadedData, fileName: entry.file)
        let didNormalize = normalizedData != downloadedData
        let importedSummary = try PatchPackageCodec.inspect(normalizedData)
        if didNormalize {
            try normalizedData.write(to: target, options: .atomic)
        }

        let importError: String? = await withCheckedContinuation { continuation in
            store.importPackage(at: target, reportsSuccess: false) { error in
                continuation.resume(returning: error)
            }
        }
        if let importError {
            throw FeedError.importFailed(importError)
        }
        UserDefaults.standard.set(entry.sha256, forKey: importedDigestKey(for: entry))
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

    private func digest(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
