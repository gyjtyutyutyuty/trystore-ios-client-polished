import Foundation
import Darwin
import CryptoKit

struct CosmeticReplacementResult: Equatable {
    let backupName: String
    let byteCount: Int64
}

enum CosmeticReplacementError: Error, LocalizedError, Equatable {
    case invalidRoot
    case targetMissing
    case targetIsDirectory
    case sourceMissing
    case sourceIsDirectory
    case symbolicLinkUnsupported
    case invalidRelativePath
    case backupFailed
    case replacementFailed
    case verificationFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidRoot: return "The selected folder is not a valid local folder."
        case .targetMissing: return "The cosmetic target file was not found in the selected folder."
        case .targetIsDirectory: return "The cosmetic target is a folder, not a file."
        case .sourceMissing: return "The bundled cosmetic resource is missing."
        case .sourceIsDirectory: return "The bundled cosmetic resource is invalid."
        case .symbolicLinkUnsupported: return "Symbolic links are not permitted in the replacement path."
        case .invalidRelativePath: return "The cosmetic path is invalid."
        case .backupFailed: return "The backup could not be created."
        case .replacementFailed: return "The replacement could not be completed atomically."
        case .verificationFailed: return "The replaced file failed verification; the backup was restored."
        case .rollbackFailed: return "Replacement failed and rollback could not be completed."
        }
    }
}

enum SafeCosmeticReplacementService {
    static let relativePath = [
        "Documents", "contentcache", "Compulsory", "ios", "gameassetbundles",
        "cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
    ]

    static func replaceChestAsset(
        in selectedRoot: URL,
        fileManager: FileManager = .default
    ) throws -> CosmeticReplacementResult {
        guard selectedRoot.isFileURL else { throw CosmeticReplacementError.invalidRoot }
        try validateRelativePath(relativePath)
        try rejectSymlinks(at: selectedRoot, components: [])

        let source = try bundledSourceURL()
        let target = try targetURL(from: selectedRoot)
        try rejectSymlinks(at: target.deletingLastPathComponent(), components: Array(relativePath.dropLast()))

        let targetValues = try resourceValues(target, missing: .targetMissing)
        guard targetValues.isDirectory != true else { throw CosmeticReplacementError.targetIsDirectory }
        guard targetValues.isSymbolicLink != true else { throw CosmeticReplacementError.symbolicLinkUnsupported }

        let sourceValues = try resourceValues(source, missing: .sourceMissing)
        guard sourceValues.isDirectory != true else { throw CosmeticReplacementError.sourceIsDirectory }
        guard sourceValues.isSymbolicLink != true else { throw CosmeticReplacementError.symbolicLinkUnsupported }

        let backupName = ".jvztxnx-backup-\(UUID().uuidString)-\(target.lastPathComponent)"
        let backupURL = target.deletingLastPathComponent().appendingPathComponent(backupName)
        let stagingURL = target.deletingLastPathComponent().appendingPathComponent(".jvztxnx-stage-\(UUID().uuidString)")

        do {
            try fileManager.copyItem(at: target, to: backupURL)
        } catch {
            throw CosmeticReplacementError.backupFailed
        }

        do {
            try copyAndSync(source: source, to: stagingURL, fileManager: fileManager)
            guard rename(stagingURL.path, target.path) == 0 else {
                throw CosmeticReplacementError.replacementFailed
            }
            let expected = try SHA256Digest.file(source)
            let actual = try SHA256Digest.file(target)
            guard expected == actual else {
                throw CosmeticReplacementError.verificationFailed
            }
            try? fileManager.removeItem(at: backupURL)
            return CosmeticReplacementResult(
                backupName: backupName,
                byteCount: (try fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            )
        } catch let error as CosmeticReplacementError {
            try? fileManager.removeItem(at: stagingURL)
            do {
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: backupURL, to: target)
            } catch {
                throw CosmeticReplacementError.rollbackFailed
            }
            if error == .verificationFailed {
                throw error
            }
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            do {
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: backupURL, to: target)
            } catch {
                throw CosmeticReplacementError.rollbackFailed
            }
            throw CosmeticReplacementError.replacementFailed
        }
    }

    private static func bundledSourceURL() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: "cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D",
            withExtension: nil
        ) else {
            throw CosmeticReplacementError.sourceMissing
        }
        return url
    }

    private static func targetURL(from selectedRoot: URL) throws -> URL {
        let normalized = selectedRoot.standardizedFileURL
        let relative: [String]
        if normalized.lastPathComponent == "Documents" {
            relative = Array(relativePath.dropFirst())
        } else {
            relative = relativePath
        }
        let target = relative.reduce(normalized) { $0.appendingPathComponent($1, isDirectory: false) }
        let canonicalRoot = normalized.resolvingSymlinksInPath().standardizedFileURL
        let canonicalTarget = target.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalTarget.path.hasPrefix(canonicalRoot.path + "/") else {
            throw CosmeticReplacementError.invalidRelativePath
        }
        return target
    }

    private static func validateRelativePath(_ components: [String]) throws {
        guard !components.isEmpty else { throw CosmeticReplacementError.invalidRelativePath }
        for component in components {
            guard !component.isEmpty,
                  component != ".",
                  component != "..",
                  !component.contains("/"),
                  !component.contains("\\") else {
                throw CosmeticReplacementError.invalidRelativePath
            }
        }
    }

    private static func rejectSymlinks(at root: URL, components: [String]) throws {
        var current = root
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw CosmeticReplacementError.symbolicLinkUnsupported
            }
        }
    }

    private static func resourceValues(
        _ url: URL,
        missing: CosmeticReplacementError
    ) throws -> URLResourceValues {
        guard FileManager.default.fileExists(atPath: url.path) else { throw missing }
        return try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
    }

    private static func copyAndSync(source: URL, to staging: URL, fileManager: FileManager) throws {
        guard fileManager.createFile(atPath: staging.path, contents: nil) else {
            throw CosmeticReplacementError.replacementFailed
        }
        defer { try? fileManager.removeItem(at: staging) }
        do {
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: staging)
            defer {
                try? input.close()
                try? output.close()
            }
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                try output.write(contentsOf: data)
            }
            try output.synchronize()
        } catch {
            throw CosmeticReplacementError.replacementFailed
        }
    }
}

enum SHA256Digest {
    static func file(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).hex
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
