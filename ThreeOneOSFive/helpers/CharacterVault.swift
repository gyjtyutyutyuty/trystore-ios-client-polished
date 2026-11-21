import CryptoKit
import Foundation

/// The character meshes ship as sealed blobs, not as an .obj folder.
/// Release builds carry `TSC2` payloads sealed under a key derived from the
/// server-released patch bundle key; debug builds may still read the historical
/// `TSC1` payloads so a checkout without the production secret opens.
enum CharacterVault {
    private enum VaultError: Error {
        case corrupt
        case missingAssets
        case unavailable
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

    private static var cacheRoot: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CharacterVault", isDirectory: true)
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
        guard let cacheRoot else { throw VaultError.unavailable }
        let stamp = cacheRoot.appendingPathComponent("v2-\(keyTag)")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: stamp.path) {
            return cacheRoot
        }

        let bundleRoot = Bundle.main.url(forResource: folder, withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent(folder, isDirectory: true)
        guard let bundleRoot else { throw VaultError.missingAssets }

        try? fileManager.removeItem(at: cacheRoot)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        guard let walker = fileManager.enumerator(at: bundleRoot, includingPropertiesForKeys: nil) else {
            throw VaultError.missingAssets
        }
        let prefix = bundleRoot.path + "/"
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

        try Data(keyTag.utf8).write(to: stamp)
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
            difference |= lhs[lhs.startIndex + index] ^ rhs[rhs.startIndex + index]
        }
        return difference == 0
    }
}
