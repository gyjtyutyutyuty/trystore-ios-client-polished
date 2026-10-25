import Darwin
import Foundation
import SwiftUI
import UIKit

enum RuntimeProbeState {
    case unavailable
    case blockedByDebug
    case blockedByInstrumentation
    case blockedBySimulator
    case ok
}

enum RuntimeProbe {
    static let targetScheme = "freefiremax"

    static func currentState() -> RuntimeProbeState {
#if targetEnvironment(simulator)
        return .blockedBySimulator
#endif
        if SecuritySuiteProbe.amIDebugged() { return .blockedByDebug }
        if SecuritySuiteProbe.hasInstrumentationLoaded() { return .blockedByInstrumentation }
        if SecuritySuiteProbe.amIRunInEmulator() { return .blockedBySimulator }
        return canOpenTarget() ? .ok : .unavailable
    }

    static func canOpenTarget() -> Bool {
        guard let url = URL(string: "\(targetScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func isDebuggerAttached() -> Bool {
        SecuritySuiteProbe.amIDebugged()
    }
}

enum SecuritySuiteProbe {
    private static let instrumentationIndicators = [
        "frida", "gadget", "objection", "debugserver", "lldb", "gdb",
        "substrate", "mobilesubstrate", "substitute", "libhooker", "ellekit",
        "rocketbootstrap", "choicy", "shadow", "cycript", "flex",
        "dobby", "whale", "fishhook", "tweakinject", "xposed"
    ]

    static func amIDebugged() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    static func amIRunInEmulator() -> Bool {
#if targetEnvironment(simulator)
        return true
#else
        let environment = ProcessInfo.processInfo.environment
        return environment["SIMULATOR_DEVICE_NAME"] != nil || environment["IPHONE_SIMULATOR_ROOT"] != nil
#endif
    }

    static func hasInstrumentationLoaded() -> Bool {
        if hasInjectedEnvironment() || hasSuspiciousArguments() { return true }

        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            let image = String(cString: name).lowercased()
            if instrumentationIndicators.contains(where: { image.contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func hasInjectedEnvironment() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let injectionKeys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH",
            "FRIDA_SERVER",
            "FRIDA_GADGET"
        ]
        return injectionKeys.contains { key in
            guard let value = environment[key], !value.isEmpty else { return false }
            return true
        }
    }

    private static func hasSuspiciousArguments() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
            .map { $0.lowercased() }
        return arguments.contains { argument in
            instrumentationIndicators.contains { argument.contains($0) }
        }
    }

    static func denyDebugger() {
#if !DEBUG
        let pointer = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(pointer, "ptrace") else { return }
        typealias PtraceType = @convention(c) (CInt, pid_t, CInt, CInt) -> CInt
        let ptrace = unsafeBitCast(symbol, to: PtraceType.self)
        _ = ptrace(31, 0, 0, 0)
#endif
    }
}
