import CryptoKit
import Foundation

extension Notification.Name {
    /// Posted after the sealed character vault finishes downloading. Art views
    /// that failed before the transfer completed listen for this.
    static let characterVaultDidChange = Notification.Name("cc.forcequit.worse-query.character-vault")
}

/// The character meshes are not shipped inside the IPA. The feed serves the
/// sealed `TSC2` blobs to a licensed device, the client verifies every blob
/// against the signed vault manifest, and the decrypted meshes go to Caches.
/// Debug builds may still read a vault folder placed in the bundle.
enum CharacterVault {
    private enum VaultError: Error {
        case corrupt
        case invalidManifest
        case missingAssets
        case unavailable
    }

    private struct VaultManifest: Decodable {
        let schemaVersion: Int
        let project: String
        let version: String
        let files: [VaultFile]
    }

    private struct VaultFile: Decodable {
        let path: String
        let sha256: String
        let size: Int
    }

    private static let folder = "CharacterVault"
    private static let magic1 = Data([0x54, 0x53, 0x43, 0x31])   // "TSC1"
    private static let magic2 = Data([0x54, 0x53, 0x43, 0x32])   // "TSC2"
    private static let nonceLength = 16
    private static let tagLength = 16
    private static let blockLength = 32
    private static let lock = NSLock()
    private static let kdfSalt = Data("trystore-character-vault-v1".utf8)
    private static let kdfInfo = Data("TSC2/key".utf8)
    private static let expectedHost = "trystore-patch-feed.burgoajustin.workers.dev"
    private static let vaultManifestPath = "api/patches/trystore/character-vault/manifest.json"
    private static let vaultBlobPath = "api/patches/trystore/character-vault/"
    private static let vaultSignatureHeader = "x-trystore-signature"
    private static let maximumFileSize = 8 * 1024 * 1024
    private static let maximumFiles = 64
    private static let supportFolder = "CharacterVaultFeed"
    private static let versionFileName = "version.txt"
    private static let syncLock = NSLock()
    private static var syncInFlight = false

    #if DEBUG
    // Historical split key. Debug builds only; Release refuses TSC1.
    private static let keyXor: [UInt8] = [0x45, 0x40, 0x08, 0x6A, 0x79, 0x5B, 0x2A, 0x74, 0x08, 0xDB, 0x8A, 0x8B, 0x75, 0xAC, 0x2B, 0x3D, 0x0C, 0x03, 0xE7, 0x45, 0x5B, 0xD2, 0xA7, 0xE1, 0xD3, 0xAD, 0xA8, 0xF3, 0x6C, 0x1F, 0xF5, 0x7B]
    private static let keyPad: [UInt8] = [0x40, 0x96, 0xF7, 0xE9, 0x5B, 0xC0, 0x83, 0xEE, 0x1A, 0xE6, 0xE9, 0xFA, 0xB5, 0x67, 0x93, 0xA7, 0xD1, 0xD0, 0x1F, 0x18, 0x5C, 0xDB, 0x42, 0x73, 0x18, 0x42, 0xEC, 0xB7, 0x4F, 0x08, 0x7F, 0xC4]
    #endif

    static func modelURL(_ model: HeroCharacterModel) -> URL? {
        guard let root = try? materialize() else { return nil }
        let url = root
            .appendingPathComponent(model.rawValue, isDirectory: true)
            .appendingPathComponent(model.objectFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download

    /// Fetch the signed vault manifest and any missing blobs. Safe to call on
    /// every launch; an unchanged version with all files present costs one
    /// request.
    static func sync(credentials: PatchFeedCredentials) async {
        guard beginSync() else { return }
        defer { endSync() }
        do {
            let changed = try await downloadIfNeeded(credentials: credentials)
            if changed { clearMaterializedCache() }
            NotificationCenter.default.post(name: .characterVaultDidChange, object: nil)
        } catch {
            log("vault: sync failed — \(error)")
        }
    }

    /// Remove both the sealed copy and the decrypted cache. Called when the
    /// licence is cleared or the runtime tamper probe fires.
    static func purge() {
        lock.lock()
        defer { lock.unlock() }
        if let root = supportRoot {
            try? FileManager.default.removeItem(at: root)
        }
        if let cache = cacheRoot {
            try? FileManager.default.removeItem(at: cache)
        }
    }

    private static func beginSync() -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        guard !syncInFlight else { return false }
        syncInFlight = true
        return true
    }

    private static func endSync() {
        syncLock.lock()
        syncInFlight = false
        syncLock.unlock()
    }

    private static func downloadIfNeeded(credentials: PatchFeedCredentials) async throws -> Bool {
        guard let baseURL = PatchResourceBundle.configuredBaseURL(),
              baseURL.host?.lowercased() == expectedHost else {
            throw VaultError.unavailable
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let manifest = try await fetchManifest(session: session, baseURL: baseURL, credentials: credentials)
        guard let root = supportRoot, let sealed = sealedRoot else {
            throw VaultError.unavailable
        }
        let fileManager = FileManager.default
        let versionURL = root.appendingPathComponent(versionFileName)
        let storedVersion = (try? String(contentsOf: versionURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedVersion == manifest.version,
           filesPresent(manifest.files, at: sealed, fileManager: fileManager) {
            return false
        }

        try? fileManager.removeItem(at: versionURL)
        try? fileManager.removeItem(at: sealed)
        try fileManager.createDirectory(at: sealed, withIntermediateDirectories: true)
        excludeFromBackup(root)
        do {
            for entry in manifest.files {
                let data = try await fetchFile(
                    session: session,
                    baseURL: baseURL,
                    entry: entry,
                    credentials: credentials
                )
                let destination = sealed.appendingPathComponent(entry.path)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: [.atomic, .completeFileProtection])
            }
            try Data(manifest.version.utf8)
                .write(to: versionURL, options: [.atomic, .completeFileProtection])
        } catch {
            // A partial vault has no version stamp, so the next sync starts
            // over instead of serving a truncated mesh.
            try? fileManager.removeItem(at: sealed)
            throw error
        }
        return true
    }

    private static func fetchManifest(
        session: URLSession,
        baseURL: URL,
        credentials: PatchFeedCredentials
    ) async throws -> VaultManifest {
        let url = baseURL.appendingPathComponent(vaultManifestPath)
        var lastError: Error = VaultError.unavailable
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(
                    for: PatchResourceBundle.authenticatedRequest(url: url, credentials: credentials)
                )
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      http.url?.host?.lowercased() == baseURL.host?.lowercased(),
                      let signature = http.value(forHTTPHeaderField: vaultSignatureHeader),
                      PatchResourceBundle.verifyManifest(data: data, signature: signature) else {
                    throw VaultError.invalidManifest
                }
                let manifest = try JSONDecoder().decode(VaultManifest.self, from: data)
                try validate(manifest)
                return manifest
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                }
            }
        }
        throw lastError
    }

    private static func fetchFile(
        session: URLSession,
        baseURL: URL,
        entry: VaultFile,
        credentials: PatchFeedCredentials
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(vaultBlobPath + entry.path)
        var lastError: Error = VaultError.unavailable
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(
                    for: PatchResourceBundle.authenticatedRequest(url: url, credentials: credentials)
                )
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      http.url?.host?.lowercased() == baseURL.host?.lowercased(),
                      data.count == entry.size,
                      data.count <= maximumFileSize else {
                    throw VaultError.unavailable
                }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
                    throw VaultError.corrupt
                }
                return data
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                }
            }
        }
        throw lastError
    }

    private static func validate(_ manifest: VaultManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.project == "trystore",
              isSafeVersion(manifest.version),
              !manifest.files.isEmpty,
              manifest.files.count <= maximumFiles else {
            throw VaultError.invalidManifest
        }
        var paths = Set<String>()
        for entry in manifest.files {
            guard isSafePath(entry.path),
                  paths.insert(entry.path).inserted,
                  entry.size > 0,
                  entry.size <= maximumFileSize,
                  isHexDigest(entry.sha256) else {
                throw VaultError.invalidManifest
            }
        }
        // A signed manifest without both meshes would leave one character
        // permanently blank; refuse it instead of caching a half vault.
        guard paths.contains("rouk/rouk.obj.tsc"),
              paths.contains("sakura/sakura.obj.tsc") else {
            throw VaultError.invalidManifest
        }
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafePath(_ path: String) -> Bool {
        guard path.count <= 96, path.hasSuffix(".tsc") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, (parts[0] == "rouk" || parts[0] == "sakura") else { return false }
        let name = String(parts[1])
        guard !name.isEmpty, name.count <= 80 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isHexDigest(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func filesPresent(
        _ files: [VaultFile],
        at root: URL,
        fileManager: FileManager
    ) -> Bool {
        for entry in files {
            let path = root.appendingPathComponent(entry.path).path
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue == entry.size else {
                return false
            }
        }
        return true
    }

    private static var supportRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(supportFolder, isDirectory: true)
    }

    private static var sealedRoot: URL? {
        supportRoot?.appendingPathComponent(folder, isDirectory: true)
    }

    private static func downloadedVaultRoot() -> URL? {
        guard let root = supportRoot,
              let sealed = sealedRoot,
              let version = try? String(contentsOf: root.appendingPathComponent(versionFileName), encoding: .utf8),
              isSafeVersion(version.trimmingCharacters(in: .whitespacesAndNewlines)),
              FileManager.default.fileExists(atPath: sealed.path) else {
            return nil
        }
        return sealed
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    // MARK: - Unseal

    private static var cacheRoot: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CharacterVault", isDirectory: true)
    }

    private static func clearMaterializedCache() {
        lock.lock()
        defer { lock.unlock() }
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
    }

    /// Release art is only readable after the feed has released the bundle key.
    /// Debug builds keep the legacy key so a local checkout still renders.
    private static func vaultKey() throws -> Data {
        if let material = PatchBundleKeyStore.cachedKey(), material.count == 32 {
            let derived = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: material),
                salt: kdfSalt,
                info: kdfInfo,
                outputByteCount: 32
            )
            return derived.withUnsafeBytes { Data($0) }
        }
        #if DEBUG
        return Data(zip(keyXor, keyPad).map { $0.0 ^ $0.1 })
        #else
        throw VaultError.unavailable
        #endif
    }

    private static func materialize() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        let key = try vaultKey()
        let keyTag = SHA256.hash(data: key).prefix(8).map { String(format: "%02x", $0) }.joined()
        guard let cache = cacheRoot else { throw VaultError.unavailable }
        let cacheRoot = cache

        let sourceRoot: URL
        #if DEBUG
        if let downloaded = downloadedVaultRoot() {
            sourceRoot = downloaded
        } else if let bundled = Bundle.main.url(forResource: folder, withExtension: nil)
                    ?? Bundle.main.resourceURL?.appendingPathComponent(folder, isDirectory: true) {
            sourceRoot = bundled
        } else {
            throw VaultError.missingAssets
        }
        #else
        guard let downloaded = downloadedVaultRoot() else { throw VaultError.missingAssets }
        sourceRoot = downloaded
        #endif

        let rawVersion = (try? String(
            contentsOf: sourceRoot.deletingLastPathComponent().appendingPathComponent(versionFileName),
            encoding: .utf8
        )) ?? "local"
        let versionTag = rawVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            .prefix(16)
        let stamp = cacheRoot.appendingPathComponent("v2-\(keyTag)-\(versionTag)")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: stamp.path) {
            return cacheRoot
        }

        try? fileManager.removeItem(at: cacheRoot)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        guard let walker = fileManager.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            throw VaultError.missingAssets
        }
        let prefix = sourceRoot.path + "/"
        while let source = walker.nextObject() as? URL {
            guard source.pathExtension == "tsc" else { continue }
            let relative = source.path.replacingOccurrences(of: prefix, with: "")
            guard relative.hasSuffix(".tsc") else { continue }
            let target = cacheRoot.appendingPathComponent(String(relative.dropLast(4)))
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let sealed = try Data(contentsOf: source)
            try decrypt(sealed, key: key).write(to: target, options: .atomic)
        }

        try Data(String("v2-\(keyTag)-\(versionTag)").utf8).write(to: stamp)
        return cacheRoot
    }

    private static func decrypt(_ sealed: Data, key: Data) throws -> Data {
        let header = 4 + nonceLength + tagLength
        guard sealed.count > header else { throw VaultError.corrupt }
        let magic = sealed.prefix(4)
        let legacy: Bool
        if magic == magic2 {
            legacy = false
        } else if magic == magic1 {
            #if DEBUG
            legacy = true
            #else
            throw VaultError.corrupt
            #endif
        } else {
            throw VaultError.corrupt
        }

        let nonce = sealed.subdata(in: 4..<(4 + nonceLength))
        let tag = sealed.subdata(in: (4 + nonceLength)..<header)
        let cipher = sealed.subdata(in: header..<sealed.count)

        let expected = hmac(key, nonce + cipher).prefix(tagLength)
        guard constantTimeEqual(Data(expected), tag) else { throw VaultError.corrupt }

        var plain = cipher
        var counter: UInt64 = 0
        var offset = 0
        while offset < plain.count {
            var input = nonce
            withUnsafeBytes(of: counter.bigEndian) { input.append(contentsOf: $0) }
            #if DEBUG
            let stream = legacy ? legacyHmac(input) : hmac(key, input)
            #else
            let stream = hmac(key, input)
            #endif
            let take = min(blockLength, plain.count - offset)
            for index in 0..<take {
                plain[offset + index] ^= stream[stream.startIndex + index]
            }
            offset += take
            counter += 1
        }
        return plain
    }

    private static func hmac(_ key: Data, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    #if DEBUG
    private static func legacyHmac(_ data: Data) -> Data {
        let key = SymmetricKey(data: Data(zip(keyXor, keyPad).map { $0.0 ^ $0.1 }))
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }
    #endif

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[lhs.startIndex + index] ^ rhs[lhs.startIndex + index]
        }
        return difference == 0
    }
}
