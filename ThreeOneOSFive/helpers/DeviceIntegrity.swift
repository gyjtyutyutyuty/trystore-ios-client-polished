import Foundation
import UIKit
import Darwin

struct DeviceIntegrityReport {
    enum Status: Equatable {
        case trusted
        case blocked(reasons: [String])

        var label: String {
            switch self {
            case .trusted: return "VERIFIED"
            case .blocked: return "REVIEW REQUIRED"
            }
        }

        var isTrusted: Bool {
            if case .trusted = self { return true }
            return false
        }
    }

    let status: Status
    let checkedAt: Date

    static func evaluate() -> DeviceIntegrityReport {
#if targetEnvironment(simulator)
        return DeviceIntegrityReport(status: .trusted, checkedAt: Date())
#else
        var reasons: [String] = []
        if debuggerAttached() { reasons.append("debugger detected") }
        if injectedLibrariesPresent() { reasons.append("injected library detected") }
        if suspiciousPathsPresent() { reasons.append("jailbreak artifact detected") }
        if Bundle.main.bundleIdentifier != "com.apple.mobile.MobileHouseArrest" { reasons.append("bundle identity mismatch") }
        if !requiredPatchResourcesPresent() { reasons.append("patch resources incomplete") }
        let status: Status = reasons.isEmpty ? .trusted : .blocked(reasons: reasons)
        return DeviceIntegrityReport(status: status, checkedAt: Date())
#endif
    }

    private static func debuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = name.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    private static func injectedLibrariesPresent() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let suspiciousKeys = ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH"]
        return suspiciousKeys.contains { key in
            guard let value = environment[key], !value.isEmpty else { return false }
            return true
        }
    }

    // RootHide can conceal jailbreak artifacts from an app, so no iOS app can
    // guarantee detection. These checks are deliberately best-effort signals:
    // known jailbreak paths, RootHide's common /var/jb location, and injection
    // indicators are evaluated, while false positives fail closed for protected actions.
    private static func suspiciousPathsPresent() -> Bool {
        let rootHidePath = "/var/jb"
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/PreferenceBundles/LibertyPref.bundle",
            rootHidePath,
            "/var/binpack",
            "/private/preboot/jailbreak"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func requiredPatchResourcesPresent() -> Bool {
        let names = [
            "AimDragFreeFire", "AimNeckFreeFire", "HSSLA",
            "HSPESCOSEMANTENA", "AimBody", "HYPERBALAMAGICA"
        ]
        return names.allSatisfy { Bundle.main.path(forResource: $0, ofType: "3105") != nil || Bundle.main.path(forResource: $0, ofType: "3105", inDirectory: "Patches") != nil }
    }
}

extension DeviceIntegrityReport.Status {
    var detail: String {
        switch self {
        case .trusted: return "Device integrity checks passed"
        case .blocked(let reasons): return reasons.joined(separator: ", ").capitalized
        }
    }
}
