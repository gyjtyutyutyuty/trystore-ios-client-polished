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
        return nil
    }

    // MARK: - Environment

    private static func hasInstrumentationEnvironment() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_FORCE_FLAT_NAMESPACE",
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
        "/Applications/Zebra.app",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/bin/bash",
        "/etc/apt",
        "/var/lib/dpkg/status",
        "/var/jb",
        "/private/preboot/jb",
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
}
