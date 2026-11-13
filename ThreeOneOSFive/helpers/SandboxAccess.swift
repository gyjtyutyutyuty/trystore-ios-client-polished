import Foundation

/// The container-access backend selected for the running OS.
///
/// - `kernel`: the kexploit_opa334 chain and sandbox_escape, iOS 17 and 18.
/// - `badQuery`: the sandbox grant used on iOS 26.0–26.6.1.
/// - `worseQuery`: the worse_query escape for iOS 26.7–26.7.2 and
///   27.0–27.3 beta 1.
/// - `unsupported`: nothing on this build; the app stays read-only.
enum SandboxBackend: String {
    case kernel
    case badQuery
    case worseQuery
    case unsupported

    var displayName: String {
        switch self {
        case .kernel: return "kernel"
        case .badQuery: return "bad_query"
        case .worseQuery: return "worse_query"
        case .unsupported: return "unsupported"
        }
    }
}

/// One place for every sandbox grant. Callers keep treating the handle as an
/// opaque `Int64`, so the file and container code does not branch per backend.
enum SandboxAccess {
    static var backend: SandboxBackend {
        let v = AppInfo.versionTuple
        if ExploitSupportPolicy.supportsKernelExploit(major: v.major, minor: v.minor, patch: v.patch) {
            return .kernel
        }
        if ExploitSupportPolicy.supportsWorseQuery(major: v.major, minor: v.minor, patch: v.patch) ||
            ExploitSupportPolicy.isExperimental(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild) {
            return .worseQuery
        }
        if ExploitSupportPolicy.supportsBadQuery(major: v.major, minor: v.minor, patch: v.patch) {
            return .badQuery
        }
        return .unsupported
    }

    private static let appGroupLock = NSLock()
    private static var cachedAppGroup: String?

    /// The group the signature granted, resolved once. A miss is not cached:
    /// the group container is created by install, but a nil result from an
    /// early launch call should not be treated as final for the process.
    static var appGroup: String? {
        appGroupLock.lock()
        defer { appGroupLock.unlock() }
        if let cached = cachedAppGroup { return cached }
        let resolved = worse_query_app_group()
        cachedAppGroup = resolved
        return resolved
    }

    static var hasAppGroup: Bool { appGroup != nil }

    static var needsWorseQuery: Bool { backend == .worseQuery }

    /// System Data and System Groups are only reachable through worse_query on
    /// iOS 27; iOS 26 keeps its earlier visibility rules.
    static var systemAreasReachable: Bool {
        switch backend {
        case .kernel, .badQuery:
            return true
        case .worseQuery:
            return AppInfo.versionTuple.major >= 27
        case .unsupported:
            return false
        }
    }

    /// True when the current backend can reach Shared/SystemGroup containers
    /// (MobileGestalt cache, ConfigurationProfiles, supervised-mode files).
    /// worse_query grants those on 26.7+, and the kernel chain escapes the
    /// sandbox entirely on 17/18. bad_query covers app containers only.
    static var systemGroupWritable: Bool {
        backend == .worseQuery || backend == .kernel
    }

    /// True when a feature needs a SystemGroup but the running backend cannot
    /// provide one.
    static var systemGroupFeaturesUnavailable: Bool {
        !systemGroupWritable
    }

    /// iOS 27.0.1 cannot list the System Groups parent; callers that need it
    /// probe the known container names instead.
    static var systemGroupParentListable: Bool {
        let version = AppInfo.versionTuple
        return !(version.major == 27 && version.minor == 0 && version.patch == 1)
    }

    /// Heals an interrupted Library/Caches swap. Called once at launch.
    static func prepare() {
        guard backend == .worseQuery else { return }
        if !worse_query_recover() {
            log("sandbox: worse_query recovery skipped or needs attention")
        }
    }

    /// A lightweight activation probe used by the UI and by the launch check.
    static func probe() -> Bool {
        switch backend {
        case .kernel:
            return KernelExploit.hasKernelSandboxAccess()
        case .badQuery:
            let handle = grant(path: ContainerStore.appDataRoot)
            if handle >= 0 {
                release(handle)
                return true
            }
            return false
        case .worseQuery:
            guard let group = appGroup,
                  let groupURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group
                  ) else {
                logOnce("sandbox-no-app-group", "sandbox: no App Group entitlement — worse_query cannot run")
                return false
            }
            // Exercise the real query path on our own group container first;
            // the parent container root is not grantable on every build.
            let groupHandle = grant(path: groupURL.path)
            if groupHandle >= 0 {
                release(groupHandle)
                return true
            }
            let handle = grant(path: ContainerStore.appDataRoot)
            if handle >= 0 {
                release(handle)
                return true
            }
            log("sandbox: worse_query probe failed on the App Group and app-data root")
            return false
        case .unsupported:
            return false
        }
    }

    static func grant(path: String) -> Int64 {
        let clean = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        switch backend {
        case .kernel, .unsupported:
            return -1
        case .badQuery:
            var pathC = clean.utf8CString.map { Int8($0) }
            return bad_query(&pathC, true, nil, false)
        case .worseQuery:
            var pathC = clean.utf8CString.map { Int8($0) }
            return worse_query_grant(&pathC)
        }
    }

    static func release(_ handle: Int64) {
        guard handle >= 0 else { return }
        switch backend {
        case .kernel, .unsupported:
            break
        case .badQuery:
            bad_query_release(handle)
        case .worseQuery:
            worse_query_release(handle)
        }
    }

    /// Container path → bundle identifier, for the builds where the metadata
    /// plist is no longer readable. Empty unless worse_query is active.
    static func pathIdentifiers() -> [String: String] {
        guard backend == .worseQuery else { return [:] }
        return worse_query_path_identifiers()
    }

    /// Bundle identifier → container path. Empty unless worse_query is active.
    static func identifierPaths() -> [String: String] {
        guard backend == .worseQuery else { return [:] }
        return worse_query_identifier_paths()
    }
}
