import Foundation
import Darwin
import UniformTypeIdentifiers

enum ReplacementPickerPolicy {
    static let allowedContentTypes: [UTType] = [.data]
    static let copiesSelectedDocument = true
    static let presentationDelay: TimeInterval = 0.35

    static func accepts(_ type: UTType) -> Bool {
        type.conforms(to: .data) && !type.conforms(to: .folder)
    }
}

struct FileReplacementSelection: Equatable {
    let targetURL: URL
    let targetName: String
    let sourceURL: URL
}

struct FileReplacementRequest: Identifiable, Equatable {
    let id: UUID
    let targetURL: URL
    let targetName: String

    init(id: UUID = UUID(), targetURL: URL, targetName: String) {
        self.id = id
        self.targetURL = targetURL
        self.targetName = targetName
    }

    func selection(from urls: [URL]) throws -> FileReplacementSelection {
        guard let sourceURL = urls.first else {
            throw FileReplacementError.sourceMissing
        }
        return FileReplacementSelection(
            targetURL: targetURL,
            targetName: targetName,
            sourceURL: sourceURL
        )
    }
}

enum FileReplacementError: Error, Equatable, LocalizedError {
    case targetMissing
    case sourceMissing
    case targetIsDirectory
    case sourceIsDirectory
    case sameFile
    case symbolicLinkUnsupported
    case sourceTooLarge
    case backupFailed
    case replacementFailed

    var errorDescription: String? {
        switch self {
        case .targetMissing: return "The target file no longer exists."
        case .sourceMissing: return "The selected replacement file is unavailable."
        case .targetIsDirectory: return "Folders cannot be replaced with this action."
        case .sourceIsDirectory: return "Select a file, not a folder."
        case .sameFile: return "A file cannot replace itself."
        case .symbolicLinkUnsupported: return "Symbolic links are not supported."
        case .sourceTooLarge: return "The selected file is too large."
        case .backupFailed: return "The original file could not be backed up."
        case .replacementFailed: return "The file could not be replaced safely."
        }
    }
}

struct FileReplacementResult: Equatable {
    let targetURL: URL
    let byteCount: Int64
    let backupURL: URL
}

/// Replaces files inside a container this process can already reach — its own
/// data container, or the App Group container named in the entitlements.
///
/// The write is a same-directory atomic swap: the original is copied into the
/// backup root, the new bytes are streamed into a sibling staging file that
/// keeps the target's permissions and protection class, and a single `rename`
/// publishes it. Nothing outside those containers is reachable by design, so
/// there is no remote or pairing path here.
enum FileReplacementService {
    private static let chunkSize = 1_024 * 1_024

    static func replace(
        target targetURL: URL,
        with sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileReplacementResult {
        let targetValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        let sourceValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        guard targetValues.isSymbolicLink != true,
              sourceValues.isSymbolicLink != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard targetValues.isDirectory != true else {
            throw FileReplacementError.targetIsDirectory
        }
        guard sourceValues.isDirectory != true else {
            throw FileReplacementError.sourceIsDirectory
        }
        guard targetURL.standardizedFileURL.resolvingSymlinksInPath()
                != sourceURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileReplacementError.sameFile
        }
        let targetAttributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        let backupURL = try backupOriginalFile(
            at: targetURL,
            fileManager: fileManager
        )
        let stagingURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".3105-replacement-\(UUID().uuidString)")
        let stagingAttributes = retainedAttributes(from: targetAttributes)
        guard fileManager.createFile(
            atPath: stagingURL.path,
            contents: nil,
            attributes: stagingAttributes
        ) else {
            throw FileReplacementError.replacementFailed
        }
        defer { try? fileManager.removeItem(at: stagingURL) }

        var copied: Int64 = 0
        do {
            let source = try FileHandle(forReadingFrom: sourceURL)
            let staging = try FileHandle(forWritingTo: stagingURL)
            defer {
                try? source.close()
                try? staging.close()
            }
            while let data = try source.read(upToCount: chunkSize), !data.isEmpty {
                let (nextCount, overflow) = copied.addingReportingOverflow(Int64(data.count))
                guard !overflow else {
                    throw FileReplacementError.sourceTooLarge
                }
                copied = nextCount
                try staging.write(contentsOf: data)
            }
            try staging.synchronize()
        } catch let error as FileReplacementError {
            throw error
        } catch {
            throw FileReplacementError.replacementFailed
        }

        let currentValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        guard currentValues.isSymbolicLink != true,
              currentValues.isDirectory != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard rename(stagingURL.path, targetURL.path) == 0 else {
            throw FileReplacementError.replacementFailed
        }
        return FileReplacementResult(
            targetURL: targetURL,
            byteCount: copied,
            backupURL: backupURL
        )
    }

    private static func backupOriginalFile(
        at targetURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        do {
            let root = AppPaths.backupsURL
                .appendingPathComponent("replacements", isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let pathLabel = targetURL.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "/", with: "__")
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = root.appendingPathComponent(
                "\(timestamp)-\(pathLabel)-\(UUID().uuidString)",
                isDirectory: false
            )
            try fileManager.copyItem(at: targetURL, to: backupURL)
            log("file replacement: backup created \(backupURL.path) from \(targetURL.path)")
            return backupURL
        } catch {
            throw FileReplacementError.backupFailed
        }
    }

    private static func values(
        for url: URL,
        missingError: FileReplacementError,
        fileManager: FileManager
    ) throws -> URLResourceValues {
        guard fileManager.fileExists(atPath: url.path) else { throw missingError }
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw missingError
        }
    }

    private static func retainedAttributes(
        from attributes: [FileAttributeKey: Any]
    ) -> [FileAttributeKey: Any] {
        var result: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] {
            result[.posixPermissions] = permissions
        }
        if let protection = attributes[.protectionKey] {
            result[.protectionKey] = protection
        }
        return result
    }
}

enum LocalDevTunnelProbe {
    static var isConnected: Bool {
        let interfaces = ipv4Interfaces()
        guard let routeAddress = routeSource(to: "10.7.0.1") else { return false }
        return interfaces.contains {
            isTunnelInterface($0.name) && $0.address == routeAddress
        }
    }

    private static func ipv4Interfaces() -> [(name: String, address: String)] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var result: [(name: String, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  let ipv4 = numericHost(address) else { continue }
            result.append((String(cString: interface.pointee.ifa_name), ipv4))
        }
        return result
    }

    private static func routeSource(to ipAddress: String) -> String? {
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(UInt16(9).bigEndian)
        guard ipAddress.withCString({ inet_pton(AF_INET, $0, &remote.sin_addr) }) == 1 else { return nil }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let connected = withUnsafePointer(to: remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard read == 0, local.sin_addr.s_addr != 0 else { return nil }
        return withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1, numericHost)
        }
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            address,
            socklen_t(MemoryLayout<sockaddr_in>.size),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else { return nil }
        return String(cString: host)
    }

    private static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }
}
