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

    // MARK: - Code signature

    /// `csops(CS_OPS_STATUS)` reports `CS_DEBUGGED` for a process launched under
    /// a debugger or a get-task-allow entitlement. A normal Release install
    /// never carries it. Failure to query is treated as healthy so an OS change
    /// cannot brick the app.
    private static func codeSignatureIsWeakened() -> Bool {
        var status: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &status) { pointer in
            syscall(169, getpid(), 0, pointer, MemoryLayout<UInt32>.size)
        }
        guard result == 0 else { return false }
        return (status & 0x1000_0000) != 0
    }
}
