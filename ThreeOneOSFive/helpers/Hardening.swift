import CryptoKit
import Darwin
import Foundation

/// Runtime tamper indicators. The checks are deliberately cheap and run on
/// launch and on every foreground transition, so a debugger or an injected
/// dylib cannot stay attached unnoticed.
enum HardeningIssue: String {
    case debugger
    case injectedLibrary
    case jailbreakFiles
    case writableSystemPath
    case instrumentationEnvironment
    case missingRestrictedSegment
    case debugServicePort
    case weakenedCodeSignature
    case modifiedBinary

    var logDescription: String {
        switch self {
        case .debugger:
            return "debugger attached"
        case .injectedLibrary:
            return "injected library loaded"
        case .jailbreakFiles:
            return "jailbreak filesystem present"
        case .writableSystemPath:
            return "system path is writable"
        case .instrumentationEnvironment:
            return "instrumentation environment present"
        case .missingRestrictedSegment:
            return "__RESTRICT guard segment absent"
        case .debugServicePort:
            return "local debug/instrumentation service reachable"
        case .weakenedCodeSignature:
            return "code signature state is not enforced"
        case .modifiedBinary:
            return "executable text differs from the archived build"
        }
    }
}

enum Hardening {
    /// Returns the first indicator found, or nil on a stock device.
    static func firstIssue() -> HardeningIssue? {
        if SecuritySuiteProbe.amIDebugged() { return .debugger }
        if hasInstrumentationEnvironment() { return .instrumentationEnvironment }
        if let image = injectedImagePath() {
            log("hardening: injected image \(image)")
            return .injectedLibrary
        }
        if hasJailbreakFiles() { return .jailbreakFiles }
        if canWriteToSystemPath() { return .writableSystemPath }
        if !hasRestrictedSegment() { return .missingRestrictedSegment }
        if hasLocalDebugService() { return .debugServicePort }
        if codeSignatureIsWeakened() { return .weakenedCodeSignature }
        if modifiedBinary() { return .modifiedBinary }
        return nil
    }

    // MARK: - Environment

    private static func hasInstrumentationEnvironment() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_FORCE_FLAT_NAMESPACE",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH",
            "DYLD_PRINT_LIBRARIES",
            "_MSSafeMode",
            "FRIDA_AGENT",
            "FRIDA_GADGET"
        ]
        for key in keys where environment[key] != nil {
            log("hardening: environment \(key)")
            return true
        }
        return false
    }

    // MARK: - Loaded images

    /// Resolved through `dlsym` so the check does not depend on a dyld import.
    private static func loadedImagePaths() -> [String] {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        typealias ImageCount = @convention(c) () -> UInt32
        typealias ImageName = @convention(c) (UInt32) -> UnsafePointer<CChar>?

        guard let countSymbol = dlsym(defaultHandle, "_dyld_image_count"),
              let nameSymbol = dlsym(defaultHandle, "_dyld_get_image_name") else {
            return []
        }
        let count = unsafeBitCast(countSymbol, to: ImageCount.self)
        let name = unsafeBitCast(nameSymbol, to: ImageName.self)

        var paths: [String] = []
        let total = count()
        guard total < 4_096 else { return paths }
        for index in 0..<total {
            guard let raw = name(index) else { continue }
            paths.append(String(cString: raw))
        }
        return paths
    }

    private static let suspiciousImageFragments = [
        "frida", "gadget", "cycript", "substrate", "substitute",
        "ellekit", "libhooker", "tweak", "inject", "sslkillswitch",
        "choicy", "fishhook", "objection", "libhooker"
    ]

    private static func injectedImagePath() -> String? {
        let bundlePath = Bundle.main.bundlePath.lowercased()
        for rawPath in loadedImagePaths() {
            let path = rawPath.lowercased()
            guard path.hasPrefix("/") else { continue }
            if path.hasPrefix("/system/") || path.hasPrefix("/usr/lib/") { continue }
            if path.hasPrefix("/private/preboot/") { continue }
            if path.hasPrefix(bundlePath) { continue }
            if suspiciousImageFragments.contains(where: { path.contains($0) }) {
                return rawPath
            }
            // Any other absolute dylib is outside the system, the preboot
            // cache and the app bundle, which is where injected code lands.
            if path.hasSuffix(".dylib") { return rawPath }
        }
        return nil
    }

    // MARK: - Filesystem

    private static let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/TrollStore.app",
        "/Library/MobileSubstrate/DynamicLibraries",
        "/Applications/Zebra.app",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/bin/bash",
        "/etc/apt",
        "/var/lib/dpkg/status",
        "/var/jb",
        "/private/preboot/jb",
        "/var/jb/usr/bin",
        "/var/jb/usr/lib",
        "/var/containers/Bundle/Application/.jbroot",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/libsubstitute.dylib",
        "/usr/lib/libellekit.dylib",
        "/usr/lib/libhooker.dylib",
        "/Library/MobileSubstrate"
    ]

    private static func hasJailbreakFiles() -> Bool {
        jailbreakPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// A stock sandbox refuses this write. A writable `/private` means the
    /// process is running outside the container it was signed for.
    private static func canWriteToSystemPath() -> Bool {
        let probe = "/private/.trystore-integrity-probe"
        guard FileManager.default.createFile(atPath: probe, contents: Data([0x00])) else {
            return false
        }
        try? FileManager.default.removeItem(atPath: probe)
        return true
    }

    // MARK: - Mach-O integrity

    /// The linker flag `-sectcreate __RESTRICT __restrict` is the only dyld
    /// switch that survives a jailbroken launch: when the segment is present,
    /// dyld ignores `DYLD_INSERT_LIBRARIES`. Its absence means the executable
    /// was rebuilt or rewritten outside this project.
    private static func hasRestrictedSegment() -> Bool {
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(handle, "_dyld_get_image_header") else { return false }
        typealias ImageHeader = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
        let header = unsafeBitCast(symbol, to: ImageHeader.self)
        guard let base = header(0) else { return false }

        // mach_header_64: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved
        guard base.load(as: UInt32.self) == 0xfeedfacf else { return false }
        let commandCount = base.load(fromByteOffset: 16, as: UInt32.self)
        guard commandCount > 0, commandCount < 4_096 else { return false }

        var cursor = base.advanced(by: 32)
        for _ in 0..<Int(commandCount) {
            let command = cursor.load(as: UInt32.self)
            let size = cursor.load(fromByteOffset: 4, as: UInt32.self)
            guard size >= 8, size <= 0x10000 else { return false }
            if command == 0x19 { // LC_SEGMENT_64
                let segmentName = String(cString: cursor.advanced(by: 8).assumingMemoryBound(to: CChar.self))
                if segmentName == "__RESTRICT" {
                    let sectionCount = cursor.load(fromByteOffset: 64, as: UInt32.self)
                    var section = cursor.advanced(by: 72)
                    for _ in 0..<Int(sectionCount) {
                        let sectionName = String(cString: section.assumingMemoryBound(to: CChar.self))
                        if sectionName == "__restrict" { return true }
                        section = section.advanced(by: 80)
                    }
                }
            }
            cursor = cursor.advanced(by: Int(size))
        }
        return false
    }

    // MARK: - Instrumentation services

    /// Frida listens on 27042 by default and its control channel on 27043.
    /// The app sandbox still allows loopback sockets, so a hit here means the
    /// process is being driven from the device itself.
    private static func hasLocalDebugService() -> Bool {
        let ports: [UInt16] = [27042, 27043]
        return ports.contains { canConnectToLoopback(port: $0) }
    }

    private static func canConnectToLoopback(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else { return false }

        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0 else { return false }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pending = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&pending, 1, 90) > 0 else { return false }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return false
        }
        return socketError == 0
    }

    // MARK: - Binary integrity

    /// SHA-256 of every `__TEXT` section, computed in the same order as
    /// `tools/macho_code_digest.py`. The archive step stores the expected value
    /// in `Info.plist`; a patcher that rewrites code or constants no longer
    /// matches, while ad-hoc signing (which only appends `__LINKEDIT` and
    /// rewrites the Mach header) does.
    private static let expectedCodeDigest: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_CODE_SHA256") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.count == 64 ? trimmed : nil
    }()

    /// Hashing six megabytes on every probe would burn battery. The executable
    /// on disk cannot change while the process is running, so one answer holds
    /// for the whole session.
    private static let archivedCodeDigest: String? = {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return codeDigest(data)
    }()

    private static func modifiedBinary() -> Bool {
        guard let expected = expectedCodeDigest else { return false }
        guard let actual = archivedCodeDigest else { return true }
        return actual != expected
    }

    static func codeDigest(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard raw.count > 32,
                  raw.load(fromByteOffset: 0, as: UInt32.self) == 0xfeedfacf else {
                return nil
            }
            let commandCount = Int(raw.load(fromByteOffset: 16, as: UInt32.self))
            guard commandCount > 0, commandCount < 4_096 else { return nil }

            var ranges: [(offset: Int, length: Int)] = []
            var cursor = 32
            for _ in 0..<commandCount {
                guard cursor + 8 <= raw.count else { return nil }
                let command = raw.load(fromByteOffset: cursor, as: UInt32.self)
                let size = Int(raw.load(fromByteOffset: cursor + 4, as: UInt32.self))
                guard size >= 8, cursor + size <= raw.count else { return nil }

                if command == 0x19 { // LC_SEGMENT_64
                    let segment = sectionName(raw, at: cursor + 8)
                    if segment == "__TEXT" {
                        let sections = Int(raw.load(fromByteOffset: cursor + 64, as: UInt32.self))
                        guard sections <= 4_096,
                              cursor + 72 + sections * 80 <= cursor + size else {
                            return nil
                        }
                        for index in 0..<sections {
                            let base = cursor + 72 + index * 80
                            let flags = raw.load(fromByteOffset: base + 64, as: UInt32.self)
                            let type = flags & 0xff
                            // Zero-fill sections carry no bytes in the file.
                            if type == 1 || type == 12 || type == 18 { continue }
                            let offset = Int(raw.load(fromByteOffset: base + 48, as: UInt32.self))
                            let length = Int(raw.load(fromByteOffset: base + 40, as: UInt64.self))
                            guard length > 0, offset >= 0, offset + length <= raw.count else { continue }
                            ranges.append((offset, length))
                        }
                    }
                }
                cursor += size
            }

            guard !ranges.isEmpty else { return nil }
            ranges.sort { $0.offset < $1.offset }
            var hasher = SHA256()
            for range in ranges {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(
                    rebasing: raw[range.offset..<range.offset + range.length]
                ))
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func sectionName(_ raw: UnsafeRawBufferPointer, at offset: Int) -> String {
        var bytes: [UInt8] = []
        for index in 0..<16 {
            let value = raw.load(fromByteOffset: offset + index, as: UInt8.self)
            if value == 0 { break }
            bytes.append(value)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Code signature

    /// `csops(CS_OPS_STATUS)` reports `CS_DEBUGGED` for a process launched under
    /// a debugger or a get-task-allow entitlement. A normal Release install
    /// never carries it. Failure to query is treated as healthy so an OS change
    /// cannot brick the app.
    private static func codeSignatureIsWeakened() -> Bool {
        // `syscall` is variadic and unavailable to Swift on the current SDK.
        // Resolve `csops` directly; failure to find it means the check is
        // skipped, which matches the "query failure is healthy" policy above.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        typealias CSOps = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let symbol = dlsym(defaultHandle, "csops") else { return false }
        let csops = unsafeBitCast(symbol, to: CSOps.self)
        var status: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &status) { pointer in
            csops(getpid(), 0, UnsafeMutableRawPointer(pointer), MemoryLayout<UInt32>.size)
        }
        guard result == 0 else { return false }
        return (status & 0x1000_0000) != 0
    }
}
