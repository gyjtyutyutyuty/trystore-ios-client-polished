import CryptoKit
import Foundation
import Security

/// A P-256 key owned by this device. On hardware it lives in the Secure
/// Enclave; the simulator and any device without a SEP fall back to a software
/// key stored in the keychain. The private half never leaves the device, so a
/// copied device UUID no longer passes for the same phone.
enum DeviceKey {
    enum KeyError: Error {
        case unavailable
        case malformed
    }

    private static let tag = Data("cc.forcequit.worse-query.device-key-v1".utf8)
    private static let lock = NSLock()
    private static var cached: SecKey?

    static func publicKeyBase64() throws -> String {
        let key = try privateKey()
        guard let publicKey = SecKeyCopyPublicKey(key),
              let raw = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              raw.count == 65, raw.first == 0x04 else {
            throw KeyError.unavailable
        }
        return raw.base64EncodedString()
    }

    static func signature(message: Data) throws -> String {
        let key = try privateKey()
        guard let der = SecKeyCreateSignature(
            key,
            .ecdsaSignatureMessageX962SHA256,
            message as CFData,
            nil
        ) as Data? else {
            throw KeyError.unavailable
        }
        return try rawSignature(fromDER: der).base64EncodedString()
    }

    /// The exact bytes the feed verifies. Purpose and device are inside the
    /// signed message so a challenge cannot be replayed against another one.
    static func message(challenge: String, project: String, deviceID: String) -> Data {
        Data("TryStore device v1\n\(challenge)\n\(project)\n\(deviceID)".utf8)
    }

    private static func privateKey() throws -> SecKey {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        if let existing = loadKey() {
            cached = existing
            return existing
        }
        if let created = try? createKey() {
            cached = created
            return created
        }
        // A duplicate usually means the first query raced a previous launch.
        if let existing = loadKey() {
            cached = existing
            return existing
        }
        throw KeyError.unavailable
    }

    private static func loadKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let value = item,
              CFGetTypeID(value) == SecKeyGetTypeID() else {
            return nil
        }
        // Safe after the CFTypeID check; the compiler rejects a conditional
        // downcast to a CoreFoundation type because it can never be nil.
        return (value as! SecKey)
    }

    private static func createKey() throws -> SecKey {
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
        if SecureEnclave.isAvailable {
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw KeyError.unavailable
        }
        return key
    }

    /// `SecKeyCreateSignature` returns X9.62 DER; WebCrypto verifies raw
    /// r||s, 32 bytes each.
    private static func rawSignature(fromDER der: Data) throws -> Data {
        let bytes = [UInt8](der)
        guard bytes.count > 8, bytes[0] == 0x30 else { throw KeyError.malformed }
        var index = 2
        if bytes[1] & 0x80 != 0 {
            let lengthBytes = Int(bytes[1] & 0x7f)
            guard lengthBytes > 0, lengthBytes <= 2, index + lengthBytes <= bytes.count else {
                throw KeyError.malformed
            }
            index += lengthBytes
        }
        guard index + 2 <= bytes.count, bytes[index] == 0x02 else { throw KeyError.malformed }
        let rLength = Int(bytes[index + 1])
        index += 2
        guard rLength > 0, index + rLength + 2 <= bytes.count, bytes[index + rLength] == 0x02 else {
            throw KeyError.malformed
        }
        var r = Array(bytes[index..<index + rLength])
        index += rLength
        let sLength = Int(bytes[index + 1])
        index += 2
        guard sLength > 0, index + sLength <= bytes.count else { throw KeyError.malformed }
        var s = Array(bytes[index..<index + sLength])
        while r.count > 32, r.first == 0 { r.removeFirst() }
        while s.count > 32, s.first == 0 { s.removeFirst() }
        guard r.count <= 32, s.count <= 32 else { throw KeyError.malformed }
        r = Array(repeating: 0, count: 32 - r.count) + r
        s = Array(repeating: 0, count: 32 - s.count) + s
        return Data(r + s)
    }
}
