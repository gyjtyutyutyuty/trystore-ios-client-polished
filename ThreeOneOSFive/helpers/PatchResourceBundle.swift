import CryptoKit
import Foundation

enum PatchResourceBundle {
    enum BundleError: Error {
        case invalidKey
        case invalidCiphertext
        case invalidArchive
    }

    static func load(using keyData: Data) throws -> [String: Data] {
        guard keyData.count == 32 else { throw BundleError.invalidKey }
        let encoded = GeneratedPatchBundle.base64Chunks.joined()
        guard let combined = Data(base64Encoded: encoded),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined) else {
            throw BundleError.invalidCiphertext
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
        } catch {
            throw BundleError.invalidCiphertext
        }
        return try parse(plaintext)
    }

    private static func parse(_ archive: Data) throws -> [String: Data] {
        let bytes = [UInt8](archive)
        guard bytes.count >= 6,
              Array(bytes[0..<4]) == Array("TBP1".utf8) else {
            throw BundleError.invalidArchive
        }

        var cursor = 4
        let count = Int(readUInt16(bytes, at: &cursor))
        guard count > 0 else { throw BundleError.invalidArchive }
        var resources: [String: Data] = [:]
        resources.reserveCapacity(count)

        for _ in 0..<count {
            guard bytes.count - cursor >= 6 else { throw BundleError.invalidArchive }
            let nameLength = Int(readUInt16(bytes, at: &cursor))
            let dataLength = Int(readUInt32(bytes, at: &cursor))
            guard nameLength > 0,
                  let nameEnd = checkedEnd(cursor, length: nameLength, limit: bytes.count),
                  let dataEnd = checkedEnd(nameEnd, length: dataLength, limit: bytes.count),
                  let name = String(bytes: bytes[cursor..<nameEnd], encoding: .utf8),
                  resources[name] == nil else {
                throw BundleError.invalidArchive
            }
            resources[name] = Data(bytes[nameEnd..<dataEnd])
            cursor = dataEnd
        }

        guard cursor == bytes.count else { throw BundleError.invalidArchive }
        return resources
    }

    private static func readUInt16(_ bytes: [UInt8], at cursor: inout Int) -> UInt16 {
        let value = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2
        return value
    }

    private static func readUInt32(_ bytes: [UInt8], at cursor: inout Int) -> UInt32 {
        let value = (UInt32(bytes[cursor]) << 24)
            | (UInt32(bytes[cursor + 1]) << 16)
            | (UInt32(bytes[cursor + 2]) << 8)
            | UInt32(bytes[cursor + 3])
        cursor += 4
        return value
    }

    private static func checkedEnd(_ start: Int, length: Int, limit: Int) -> Int? {
        let (end, overflow) = start.addingReportingOverflow(length)
        return !overflow && end <= limit ? end : nil
    }
}
