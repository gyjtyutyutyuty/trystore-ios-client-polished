import Foundation
import Darwin
import UIKit

// MARK: - Models

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let containerPath: String
    let version: String
    let icon: UIImage?

    var id: String { bundleID }
    var displayName: String {
        AppDisplayNamePolicy.resolve(bundleID: bundleID, candidates: [name])
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FileEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64

    var id: String { path }
    var sizeText: String {
        if isDirectory { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Store

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    /// Any non-kernel backend needs an explicit grant before a container read.
    private static var usesSandboxGrants: Bool {
        switch SandboxAccess.backend {
        case .badQuery, .worseQuery: return true
        case .kernel, .unsupported: return false
        }
    }
    private static let applicationBundleRoots: [(path: String, nested: Bool)] = [
        ("/var/containers/Bundle/Application", true),
        ("/Applications", false),
        ("/System/Applications", false)
    ]
    static let researchAppIdentifiers = [
        "com.apple.mobilesafari", "com.apple.mobilenotes", "com.apple.Maps",
        "com.apple.facetime", "com.apple.iBooks", "com.apple.podcasts",
        "com.apple.PosterBoard", "com.apple.mobilemail", "com.apple.weather",
        "com.apple.camera", "com.apple.Health", "com.apple.Fitness",
        "com.apple.tips", "com.apple.Passbook", "com.apple.reminders",
        "com.apple.stocks", "com.apple.news", "com.apple.Home", "com.apple.tv",
        "com.apple.shortcuts", "com.apple.freeform", "com.apple.calculator",
        "com.apple.MobileSMS", "com.apple.InCallService", "com.apple.Preferences",
        "com.apple.springboard", "com.apple.Photos", "com.apple.AppStore",
        "com.apple.Music", "com.apple.Bridge", "com.apple.Clock",
        "com.apple.VoiceMemos", "com.apple.Translate", "com.apple.measure",
        "com.apple.compass", "com.apple.Magnifier", "com.apple.DocumentsApp"
    ]

    static func resolveAppContainerPath(bundleID: String) -> String? {
        guard (try? PatchPathValidator.canonicalBundleIdentifier(bundleID)) == bundleID else {
            return nil
        }
        // This process can always read its own data container, so a project
        // that targets the app itself resolves without any container-manager
        // lookup. Every other identifier falls through to the backends below.
        if let ownBundleID = Bundle.main.bundleIdentifier, bundleID == ownBundleID {
            let home = NSHomeDirectory()
            if isApplicationContainerPath(home) {
                log("patch: own container resolved \(bundleID)")
                return home
            }
        }

        // iOS 27: lsd's store pairs the identifier with its data container
        // even when MCM refuses the lookup and LaunchServices has no URL.
        // This is the step that keeps patch targets resolvable on 27.0.x.
        if let mapped = launchServicesSnapshot()?.containerPath(forBundleID: bundleID),
           isApplicationContainerPath(mapped) {
            log("patch: LaunchServices store resolved \(bundleID)")
            return mapped
        }

        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            log("patch: MHA-C2 resolved \(bundleID)")
            return path
        }
        // MCM refusing a lookup is expected on 27, so this stays quiet until
        // every fallback below has also declined; printing it here made a
        // successful LaunchServices or identifier resolution look like an error.
        let detail = lookupError.map(String.init) ?? "unavailable"

        // iOS 27: MCM refuses the lookup for this process (posix=0, meaning
        // entitlement, not a missing app), but LaunchServices still reports the
        // data container and worse_query grants the path itself. Ask LS before
        // walking the filesystem, which cannot see other apps' metadata here.
        if let info = appInfoForBundleID(bundleID) as? [String: Any],
           let lsContainer = info["container"] as? String,
           isApplicationContainerPath(lsContainer) {
            let canonical = ContainerDiscoveryMerger.canonicalPath(lsContainer)
            log("patch: LaunchServices resolved \(bundleID)")
            return canonical
        }

        // iOS 27: the metadata plist is gone and MCM lookups are denied, but
        // every container still carries its bundle identifier in the
        // `com.apple.containermanager.identifier` xattr, which becomes readable
        // once worse_query has granted that container. The escape refuses the
        // parent data root, so this walks container by container and caches the
        // result — one scan, then every rule resolves from the index.
        if let identified = locateContainerByIdentifier(bundleID) {
            log("patch: container identifier index resolved \(bundleID)")
            return identified
        }

        // Fallback for iOS builds where MCM refuses to hand out sandbox
        // tokens (e.g. iOS 18.1.x): worse_query can rebuild the container
        // index from the container manager even after the metadata plist and
        // identifier xattr disappear (iOS 27.2+). Ask it before the inode
        // scan, which reads files that no longer carry the identifier.
        if let mapped = SandboxAccess.identifierPaths()[bundleID],
           isApplicationContainerPath(mapped) {
            log("patch: worse_query identifier map resolved \(bundleID)")
            return mapped
        }
        if let reverse = SandboxAccess.pathIdentifiers()
            .first(where: { $0.value == bundleID })?.key,
           isApplicationContainerPath(reverse) {
            log("patch: worse_query reverse map resolved \(bundleID)")
            return reverse
        }
        if let scanned = resolveAppContainerPathByMetadataScan(bundleID: bundleID) {
            log("patch: filesystem metadata scan resolved \(bundleID)")
            return scanned
        }
        log("patch: unresolved \(bundleID) — MCM=\(detail), no LaunchServices container, no container identifier or metadata match")
        return nil
    }

    private static var identifierIndex: [String: String] = [:]
    private static var identifierIndexAt = Date.distantPast
    private static let identifierIndexLifetime: TimeInterval = 120

    private static func containerDirectories() -> [String] {
        enumerateDirectories(path: appDataRoot).filter {
            UUID(uuidString: ($0 as NSString).lastPathComponent) != nil
        }
    }

    /// Bundle identifier → data container, read from each container's
    /// `com.apple.containermanager.identifier` extended attribute. This is the
    /// only mapping iOS 27 still exposes once MCM refuses lookups. Reading the
    /// attribute often needs no grant; when it does, the caller falls through to
    /// `locateContainerByIdentifier`, which grants one container at a time.
    static func containerIdentifierIndex(force: Bool = false) -> [String: String] {
        if !force, !identifierIndex.isEmpty,
           Date().timeIntervalSince(identifierIndexAt) < identifierIndexLifetime {
            return identifierIndex
        }
        let directories = containerDirectories()
        guard !directories.isEmpty else {
            log("patch: container identifier scan found no containers")
            return identifierIndex
        }
        var index: [String: String] = [:]
        for directory in directories {
            guard let identifier = containerIdentifier(atPath: directory) else { continue }
            index[identifier] = ContainerDiscoveryMerger.canonicalPath(directory)
        }
        if !index.isEmpty {
            identifierIndex = index
            identifierIndexAt = Date()
        }
        log("patch: container identifiers readable without a grant: \(index.count)/\(directories.count)")
        return index
    }

    /// Walks containers until one reports `bundleID`, consuming a worse_query
    /// grant for each. The escape refuses the parent data root, so there is no
    /// single directory to grant; one container at a time is the only way in.
    /// Skipped on the main thread — a full walk can take a minute.
    static func locateContainerByIdentifier(_ bundleID: String) -> String? {
        if let mapped = containerIdentifierIndex()[bundleID] { return mapped }
        guard SandboxAccess.backend == .worseQuery, !Thread.isMainThread else { return nil }
        for directory in containerDirectories() {
            if Task.isCancelled { return nil }
            let handle = SandboxAccess.grant(path: directory)
            if handle < 0 { continue }
            defer { SandboxAccess.release(handle) }
            // The xattr is the 27.2+ source; the metadata plist still exists on
            // 27.0-27.1 and carries the same bundle identifier once the grant
            // makes the container readable.
            var identifier = containerIdentifier(atPath: directory)
            if identifier == nil,
               let metadata = readContainerMetadata(containerPath: directory) {
                identifier = metadata.bundleID
            }
            guard let identifier else { continue }
            identifierIndex[identifier] = ContainerDiscoveryMerger.canonicalPath(directory)
            identifierIndexAt = Date()
            if identifier == bundleID {
                log("patch: granted container scan resolved \(bundleID)")
                return identifierIndex[bundleID]
            }
        }
        log("patch: granted container scan found no container for \(bundleID)")
        return nil
    }

    private static func containerIdentifier(atPath path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 512)
        let length = getxattr(path, "com.apple.containermanager.identifier", &buffer, 511, 0, 0)
        guard length > 0 else { return nil }
        let identifier = String(cString: buffer)
        return identifier.isEmpty ? nil : identifier
    }

    static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? {
        // iOS < 26: kernel R/W is enough, no need to require full sandbox escape
        if KernelExploit.requiresSandboxEscape, !KernelExploit.hasSandboxAccess() {
            log("patch: metadata scan skipped — sandbox access not active")
            return nil
        }
        let dirs = enumerateDirectories(path: appDataRoot)
        guard !dirs.isEmpty else {
            log("patch: metadata scan unavailable — no containers enumerated")
            return nil
        }
        for dir in dirs {
            guard UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
            guard let metadata = readContainerMetadata(containerPath: dir),
                  metadata.bundleID == bundleID else { continue }
            let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
            guard isApplicationContainerPath(canonical) else { continue }
            return canonical
        }
        return nil
    }

    // MARK: Primary — MobileInstallation / LSApplicationWorkspace

    static func installedAppsFromAPI() -> [InstalledApp] {
        let raw = installedAppInfo() as? [String: [String: Any]] ?? [:]
        var apps: [InstalledApp] = []
        var missingContainer = 0
        for (bundleID, info) in raw {
            var containerPath = info["container"] as? String ?? ""
            if containerPath.isEmpty {
                var lookupError: NSString?
                if let resolved = MCMActivateContainerPath(2, bundleID, false, &lookupError),
                   isApplicationContainerPath(resolved) {
                    containerPath = resolved
                } else {
                    missingContainer += 1
                }
            }
            // Skip entries we cannot browse — empty path is dropped by mergers anyway.
            guard !containerPath.isEmpty else { continue }
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: info["name"] as? String ?? "",
                containerPath: containerPath,
                version: info["version"] as? String ?? "",
                icon: info["icon"] as? UIImage
            ))
        }
        log("browser: LS/API apps=\(apps.count) raw=\(raw.count) missingContainer=\(missingContainer)")
        return apps
    }

    static func applicationBundleMetadataCatalog() -> [String: ApplicationBundleMetadata] {
        var catalog: [String: ApplicationBundleMetadata] = [:]
        for root in applicationBundleRoots {
            for metadata in applicationBundleMetadata(at: root.path, nested: root.nested) {
                catalog[metadata.bundleID] = metadata
            }
        }
        log("browser: app-bundle metadata resolved \(catalog.count) names")
        return catalog
    }

    static func applyingBundleMetadata(
        to apps: [InstalledApp],
        catalog: [String: ApplicationBundleMetadata]
    ) -> [InstalledApp] {
        apps.map { app in
            guard let metadata = catalog[app.bundleID] else { return app }
            return InstalledApp(
                bundleID: app.bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: app.bundleID,
                    candidates: [metadata.displayName, app.name]
                ),
                containerPath: app.containerPath,
                version: app.version.isEmpty ? metadata.version : app.version,
                icon: app.icon
            )
        }
    }

    static func dynamicAppIdentifiers() -> [String] {
        var enumerationError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1_024, &enumerationError)
        let enumerationDetail = enumerationError.map { String($0) } ?? "none"
        log("browser: MCM class-2 identifiers=\(identifiers.count) detail=\(enumerationDetail)")
        return identifiers
    }

    static func installedAppsFromMCM(
        identifiers: [String]? = nil,
        bundleMetadata: [String: ApplicationBundleMetadata] = [:]
    ) -> [InstalledApp] {
        let identifiers = identifiers ?? dynamicAppIdentifiers()

        var apps: [InstalledApp] = []
        for (index, bundleID) in identifiers.enumerated() {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(2, bundleID, false, &lookupError) else {
                let lookupDetail = lookupError.map { String($0) } ?? "no path"
                if index < 3 { log("mcm[\(index)]: \(bundleID) -> \(lookupDetail)") }
                continue
            }
            if index < 3 { log("mcm[\(index)]: \(bundleID) -> \(containerPath)") }

            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                containerPath: containerPath,
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                icon: rawInfo["icon"] as? UIImage
            ))
        }
        log("browser: MCM resolved \(apps.count)/\(identifiers.count) app paths")
        return apps
    }

    // MARK: LaunchServices store discovery

    static func installedAppsFromMHACandidates(
        identifiers: [String],
        bundleMetadata: [String: ApplicationBundleMetadata] = [:],
        progress: (([InstalledApp]) -> Void)? = nil
    ) -> [InstalledApp] {
        guard !identifiers.isEmpty else {
            log("browser: MHA catalog returned no bundle candidates")
            return []
        }

        var apps: [InstalledApp] = []
        for (index, bundleID) in identifiers.enumerated() {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(
                2,
                bundleID,
                false,
                &lookupError
            ),
                  isApplicationContainerPath(containerPath) else {
                if index < 3 {
                    let detail = lookupError.map { String($0) } ?? "invalid app-data path"
                    log("mha-candidate[\(index)]: \(bundleID) -> \(detail)")
                }
                continue
            }

            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                containerPath: containerPath,
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                icon: rawInfo["icon"] as? UIImage
            ))
            if apps.count <= 5 {
                log("browser: MHA-C2 resolved \(bundleID) -> \(containerPath)")
            }
            if apps.count.isMultiple(of: 8) {
                progress?(apps)
            }
        }

        progress?(apps)
        log("browser: MHA-C2 resolved \(apps.count)/\(identifiers.count) bundle candidates")
        return apps
    }

    private static func applicationBundleMetadata(
        at rootPath: String,
        nested: Bool
    ) -> [ApplicationBundleMetadata] {
        let handle = grantContainerAccess(rootPath)
        defer {
            if handle >= 0 { SandboxAccess.release(handle) }
        }

        let fileManager = FileManager.default
        guard let rootEntries = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            log("browser: app-bundle metadata unavailable root=\(rootPath) grant=\(handle)")
            return []
        }

        let bundlePaths: [String]
        if nested {
            bundlePaths = rootEntries.prefix(2_048).flatMap { entry -> [String] in
                guard UUID(uuidString: entry) != nil else { return [] }
                let containerPath = (rootPath as NSString).appendingPathComponent(entry)
                let children = (try? fileManager.contentsOfDirectory(atPath: containerPath)) ?? []
                return children.prefix(16).compactMap { child in
                    guard child.hasSuffix(".app") else { return nil }
                    return (containerPath as NSString).appendingPathComponent(child)
                }
            }
        } else {
            bundlePaths = rootEntries.prefix(2_048).compactMap { entry in
                guard entry.hasSuffix(".app") else { return nil }
                return (rootPath as NSString).appendingPathComponent(entry)
            }
        }

        return bundlePaths.compactMap { bundlePath in
            let infoPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
            let infoSize = (try? fileManager.attributesOfItem(atPath: infoPath)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard infoSize > 0, infoSize <= 2 * 1_024 * 1_024 else { return nil }
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPath)) else {
                return nil
            }
            return ApplicationBundleMetadataReader.metadata(
                from: plistData,
                localizedInfo: Bundle(path: bundlePath)?.localizedInfoDictionary
            )
        }
    }

    static func launchServicesStoreIdentifiers() -> [String] {
        var cachePaths: [String] = []
        var seenCachePaths = Set<String>()

        func addCachePath(_ rawPath: String) {
            let path = ContainerDiscoveryMerger.canonicalPath(rawPath)
            guard !path.isEmpty, seenCachePaths.insert(path).inserted else { return }
            cachePaths.append(path)
        }

        var leasedCachePaths = Set<String>()
        var serviceLookupError: NSString?
        if let servicePath = MCMActivateContainerPath(
            10,
            "com.apple.lsd",
            false,
            &serviceLookupError
        ) {
            let cachePath = (servicePath as NSString).appendingPathComponent("Library/Caches")
            addCachePath(cachePath)
            leasedCachePaths.insert(ContainerDiscoveryMerger.canonicalPath(cachePath))
        } else if usesSandboxGrants {
            let detail = serviceLookupError.map { String($0) } ?? "no path"
            log("browser: MCM com.apple.lsd activation unavailable detail=\(detail)")
        }

        let traversedSystemDirectories = enumerateDirectoriesWithTraversalGrant(path: systemDataRoot)
        let systemDirectories = traversedSystemDirectories.isEmpty
            ? enumerateDirectories(path: systemDataRoot)
            : traversedSystemDirectories
        for directory in systemDirectories {
            // Attempt the raw metadata read even without a traversal grant:
            // it succeeds when the sandbox escape is active, which is the
            // only path left when MCM/bad_query grants are denied.
            guard readContainerMetadata(containerPath: directory)?.bundleID == "com.apple.lsd" else {
                continue
            }
            addCachePath((directory as NSString).appendingPathComponent("Library/Caches"))
        }

        // Older and Simulator layouts keep the same store outside the MCM
        // service-container layout. They are harmless fallbacks on device.
        addCachePath("/var/db/lsd")
        addCachePath("/var/mobile/Library/Caches")

        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()
        let maximumCandidateCount = 65_536

        for cachePath in cachePaths where identifiers.count < maximumCandidateCount {
            let hasLease = leasedCachePaths.contains(
                ContainerDiscoveryMerger.canonicalPath(cachePath)
            )
            let handle: Int64
            if hasLease || !usesSandboxGrants {
                handle = -1
            } else {
                handle = grantContainerAccess(cachePath)
                if handle < 0 {
                    log("browser: LaunchServices traversal grant failed \(cachePath) -> \(handle)")
                    continue
                }
            }
            defer {
                if handle >= 0 { SandboxAccess.release(handle) }
            }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: cachePath)) ?? []
            for name in names where identifiers.count < maximumCandidateCount {
                guard name.hasPrefix("com.apple.LaunchServices-"),
                      name.hasSuffix("-v2.csstore") else {
                    continue
                }
                let storePath = (cachePath as NSString).appendingPathComponent(name)
                guard let size = (try? FileManager.default.attributesOfItem(atPath: storePath)[.size]) as? NSNumber,
                      size.uint64Value > 0,
                      size.uint64Value <= 64 * 1_024 * 1_024,
                      let data = try? Data(contentsOf: URL(fileURLWithPath: storePath), options: .mappedIfSafe) else {
                    continue
                }
                let remaining = maximumCandidateCount - identifiers.count
                let extracted = LaunchServicesCandidateExtractor.identifiers(from: data, limit: remaining)
                for identifier in extracted where seenIdentifiers.insert(identifier).inserted {
                    identifiers.append(identifier)
                }
                log("browser: LaunchServices store \(name) bytes=\(data.count) candidates=\(identifiers.count)")
            }
        }

        log("browser: LaunchServices store total candidates=\(identifiers.count)")
        return identifiers
    }

    // MARK: LaunchServices store snapshot
    //
    // MCM refuses third-party lookups on iOS 27 and the container identifier
    // xattr/metadata plist are not always readable. lsd's CSStore still pairs
    // a bundle id with its data container, so read that pairing before asking
    // MCM or walking the app-data root. The parser is the WQ Files port in
    // LaunchServicesStore.swift.

    private struct LaunchServicesStoreCandidate {
        let url: URL
        let parentPath: String
        let modifiedAt: Date
        let size: Int
    }

    private static let launchServicesSnapshotLock = NSLock()
    private static var launchServicesSnapshotCache:
        (signature: String, snapshot: LaunchServicesSnapshot?, at: Date)?

    static func refreshLaunchServicesSnapshot() {
        launchServicesSnapshotLock.lock()
        launchServicesSnapshotCache = nil
        launchServicesSnapshotLock.unlock()
    }

    static func launchServicesSnapshot() -> LaunchServicesSnapshot? {
        launchServicesSnapshotLock.lock()
        defer { launchServicesSnapshotLock.unlock() }

        if let cached = launchServicesSnapshotCache {
            // A miss can happen before the escape is active; retry it soon
            // instead of hiding the store for the whole cache window.
            let lifetime: TimeInterval = cached.snapshot == nil ? 10 : 300
            if Date().timeIntervalSince(cached.at) < lifetime {
                return cached.snapshot
            }
        }

        let candidates = launchServicesStoreCandidates()
        guard let newest = candidates.max(by: { left, right in
            if left.modifiedAt != right.modifiedAt {
                return left.modifiedAt < right.modifiedAt
            }
            return left.size < right.size
        }) else {
            launchServicesSnapshotCache = ("none", nil, Date())
            log("patch: LaunchServices store not found")
            return nil
        }

        let signature = "\(newest.url.path)|\(newest.size)|\(newest.modifiedAt.timeIntervalSince1970)"
        if let cached = launchServicesSnapshotCache, cached.signature == signature {
            launchServicesSnapshotCache = (signature, cached.snapshot, Date())
            return cached.snapshot
        }

        let handle = usesSandboxGrants ? grantContainerAccess(newest.parentPath) : -1
        defer {
            if handle >= 0 { SandboxAccess.release(handle) }
        }
        guard let data = try? Data(contentsOf: newest.url, options: .mappedIfSafe),
              data.count <= LaunchServicesStore.maximumStoreBytes else {
            launchServicesSnapshotCache = (signature, nil, Date())
            log("patch: LaunchServices store read failed \(newest.url.lastPathComponent)")
            return nil
        }
        guard let snapshot = LaunchServicesStore.parse(data) else {
            launchServicesSnapshotCache = (signature, nil, Date())
            log("patch: LaunchServices store parse failed \(newest.url.lastPathComponent) bytes=\(data.count)")
            return nil
        }

        launchServicesSnapshotCache = (signature, snapshot, Date())
        log(
            "patch: LaunchServices layout=\(snapshot.layoutLabel) " +
                "containers=\(snapshot.mappedContainerCount) bytes=\(data.count)"
        )
        return snapshot
    }

    private static func launchServicesStoreCandidates() -> [LaunchServicesStoreCandidate] {
        var candidates: [LaunchServicesStoreCandidate] = []
        var visited = Set<String>()

        func inspect(_ rawPath: String) {
            let directory = canonicalLookupPath(rawPath)
            guard visited.insert(directory).inserted else { return }

            let handle = usesSandboxGrants ? grantContainerAccess(directory) : -1
            defer {
                if handle >= 0 { SandboxAccess.release(handle) }
            }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for name in names
            where name.hasPrefix("com.apple.LaunchServices-") && name.hasSuffix(".csstore") {
                let path = (directory as NSString).appendingPathComponent(name)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let sizeNumber = attributes[.size] as? NSNumber,
                      sizeNumber.intValue >= LaunchServicesStore.minimumStoreBytes,
                      sizeNumber.intValue <= LaunchServicesStore.maximumStoreBytes,
                      let modifiedAt = attributes[.modificationDate] as? Date,
                      let header = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
                    continue
                }
                let magic = (try? header.read(upToCount: 4)) ?? Data()
                try? header.close()
                guard magic == Data([0x62, 0x64, 0x73, 0x6c]) else { continue }
                candidates.append(LaunchServicesStoreCandidate(
                    url: URL(fileURLWithPath: path),
                    parentPath: directory,
                    modifiedAt: modifiedAt,
                    size: sizeNumber.intValue
                ))
            }
        }

        var serviceLookupError: NSString?
        if let servicePath = MCMActivateContainerPath(10, "com.apple.lsd", false, &serviceLookupError) {
            inspect((servicePath as NSString).appendingPathComponent("Library/Caches"))
        }
        inspect("/var/mobile/Library/Caches")
        inspect("/var/db/lsd")

        // iOS 27.2 moved lsd's store under the Internal Daemon containers.
        // Only pay for that walk when the classic locations came back empty.
        if candidates.isEmpty {
            for root in ["/var/mobile/Containers/Data/InternalDaemon", systemDataRoot] {
                let containers = enumerateDirectoriesWithTraversalGrant(path: root)
                for container in containers {
                    inspect((container as NSString).appendingPathComponent("Library/Caches"))
                }
            }
        }
        return candidates
    }

    /// Canonical form for paths handed to the container manager, which spells
    /// the /var alias as /private/var.
    static func canonicalLookupPath(_ path: String) -> String {
        let clean = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        if clean == "/var" || clean.hasPrefix("/var/") {
            return "/private" + clean
        }
        return clean
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = ContainerDiscoveryMerger.canonicalPath(appDataRoot)
        let canonicalPath = ContainerDiscoveryMerger.canonicalPath(path)
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { return false }
        return UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    // MARK: Filesystem discovery

    static func enumerateDirectories(path: String, maxInode: Int64 = 2_000_000) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return [] }

        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }

        // worse_query hands out a grant per path; retry the read under it
        // before the inode walk, which needs a kernel path. The data root is
        // deliberately skipped: the escape refuses a non-container target, so
        // granting it only costs a query and logs a spurious failure.
        if SandboxAccess.backend == .worseQuery, clean != appDataRoot {
            let handle = SandboxAccess.grant(path: clean)
            if handle >= 0 {
                defer { SandboxAccess.release(handle) }
                if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
                    log("enumerate: worse_query grant for \(clean) -> \(names.count) entries")
                    return names.map { (clean as NSString).appendingPathComponent($0) }
                }
            }
        }

        // fsgetpath sweep: works when FileManager and the MCM grant both
        // refuse, and it is the fallback that still finds containers on
        // 26.5+ layouts where bad_query_list comes back empty.
        let wantsPrivatePrefix = clean.hasPrefix("/private/")
        let dynamicCeiling = Pathleak.dynamicMaxInode(directory: clean, ceiling: UInt64(max(1, maxInode)))
        let leaked = Pathleak.list(directory: clean, maxInode: dynamicCeiling)
        if !leaked.isEmpty {
            log("enumerate: pathleak for \(clean) -> \(leaked.count) entries")
            return wantsPrivatePrefix ? leaked.map { "/private" + $0 } : leaked
        }

        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, maxInode) else {
            log("enumerate: NULL for \(clean)")
            return []
        }
        defer { free(result) }
        let list = String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
        if !list.isEmpty {
            log("enumerate: inode fallback for \(clean) -> \(list.count) entries")
        } else {
            log("enumerate: FileManager+inode unavailable for \(clean)")
        }
        return list
    }

    static func enumerateDirectoriesWithTraversalGrant(path: String) -> [String] {
        if !usesSandboxGrants {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
            return enumerateDirectories(path: path)
        }

        let handle = grantContainerAccess(path)
        if handle >= 0 {
            defer { SandboxAccess.release(handle) }
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
        } else {
            log("browser: root traversal grant failed \(path) -> \(handle)")
        }

        return enumerateDirectories(path: path)
    }

    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metadataPath = metadataPath(for: containerPath)

        var data: Data?
        if let fd = fopen(metadataPath, "r") {
            var buffer = [UInt8](repeating: 0, count: 65536)
            var bytes: [UInt8] = []
            while true {
                let n = fread(&buffer, 1, buffer.count, fd)
                if n <= 0 { break }
                bytes.append(contentsOf: buffer[0..<n])
            }
            fclose(fd)
            if !bytes.isEmpty { data = Data(bytes) }
        }
        if data == nil { data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) }

        guard let validData = data,
              let plist = try? PropertyListSerialization.propertyList(from: validData, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let bundleID = plist["MCMMetadataIdentifier"] as? String ?? ""
        var displayName = ""
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
        }
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }

    static func metadataPath(for containerPath: String) -> String {
        (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
    }

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        guard usesSandboxGrants else { return -1 }
        return SandboxAccess.grant(path: containerPath)
    }

    static func containersFromFilesystem() -> [InstalledApp] {
        let grantedDirectories = enumerateDirectoriesWithTraversalGrant(path: appDataRoot)
        let dirs: [String]
        if grantedDirectories.isEmpty {
            dirs = enumerateDirectories(path: appDataRoot)
            log("browser: filesystem root=\(appDataRoot) inode fallback enumerated \(dirs.count) containers")
        } else {
            dirs = grantedDirectories
            log("browser: filesystem root=\(appDataRoot) traversal enumerated \(dirs.count) containers")
        }
        // iOS 27.2 stopped exposing the container identifier xattr and the
        // metadata plist; worse_query rebuilds the map from the container
        // manager itself, so resolve names through it before falling back.
        let identifierMap = SandboxAccess.pathIdentifiers()
        let apps = dirs.compactMap { dir -> InstalledApp? in
            let uuid = (dir as NSString).lastPathComponent
            guard UUID(uuidString: uuid) != nil else { return nil }
            let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
            let mappedBundleID = identifierMap[canonical] ?? identifierMap[dir]
            if let mappedBundleID,
               !mappedBundleID.hasPrefix("systemgroup."),
               ContainerBundleCandidateResolver.isValidBundleIdentifier(mappedBundleID) {
                let info = appInfoForBundleID(mappedBundleID) as? [String: Any] ?? [:]
                return InstalledApp(
                    bundleID: mappedBundleID,
                    name: AppDisplayNamePolicy.resolve(
                        bundleID: mappedBundleID,
                        candidates: [info["name"] as? String]
                    ),
                    containerPath: dir,
                    version: info["version"] as? String ?? "",
                    icon: info["icon"] as? UIImage
                )
            }
            let fallback = ContainerIdentityResolver.fallbackIdentity(containerPath: dir)
            return InstalledApp(
                bundleID: fallback.bundleID,
                name: fallback.displayName,
                containerPath: dir,
                version: "",
                icon: nil
            )
        }
        log("browser: filesystem accepted \(apps.count)/\(dirs.count) app containers")
        return apps
    }

    static func inferredApp(
        for fallback: InstalledApp,
        knownAppsByBundleID: [String: InstalledApp],
        launchServicesIdentifiers: Set<String>
    ) -> InstalledApp? {
        guard UUID(uuidString: fallback.bundleID) != nil else { return fallback }

        // Read the MCM metadata plist directly. With the sandbox escape
        // active the raw read succeeds even when every MCM/bad_query grant
        // is denied; without it the read simply fails and we fall through.
        if let metadata = readContainerMetadata(containerPath: fallback.containerPath) {
            let bundleID = metadata.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if ContainerBundleCandidateResolver.isValidBundleIdentifier(bundleID),
               !bundleID.hasPrefix("systemgroup.") {
                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                let resolvedName = metadata.displayName.isEmpty
                    ? (info["name"] as? String ?? bundleID)
                    : metadata.displayName
                return InstalledApp(
                    bundleID: bundleID,
                    name: resolvedName,
                    containerPath: fallback.containerPath,
                    version: info["version"] as? String ?? "",
                    icon: info["icon"] as? UIImage
                )
            }
        }

        let handle = grantContainerAccess(fallback.containerPath)
        defer {
            if handle >= 0 { SandboxAccess.release(handle) }
        }

        let libraryPath = (fallback.containerPath as NSString).appendingPathComponent("Library")
        let savedStatePath = (libraryPath as NSString).appendingPathComponent("Saved Application State")
        let preferencesPath = (libraryPath as NSString).appendingPathComponent("Preferences")
        let savedStates = (try? FileManager.default.contentsOfDirectory(atPath: savedStatePath)) ?? []
        let preferences = (try? FileManager.default.contentsOfDirectory(atPath: preferencesPath)) ?? []
        let strongCandidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: savedStates,
            preferenceFileNames: []
        )
        let candidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: savedStates,
            preferenceFileNames: preferences
        )

        func resolvedApp(from candidates: [String], source: String) -> InstalledApp? {
            for bundleID in candidates {
                if let known = knownAppsByBundleID[bundleID] {
                    return InstalledApp(
                        bundleID: bundleID,
                        name: known.name,
                        containerPath: fallback.containerPath,
                        version: known.version,
                        icon: known.icon
                    )
                }

                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                guard info["found"] as? Bool == true else { continue }
                return InstalledApp(
                    bundleID: bundleID,
                    name: info["name"] as? String ?? bundleID,
                    containerPath: fallback.containerPath,
                    version: info["version"] as? String ?? "",
                    icon: info["icon"] as? UIImage
                )
            }

            guard let bundleID = ContainerBundleCandidateResolver.confirmedCandidate(
                candidates: candidates,
                launchServicesIdentifiers: launchServicesIdentifiers
            ) else {
                return nil
            }
            let uuid = (fallback.containerPath as NSString).lastPathComponent
            log("browser: content+LaunchServices confirmed \(uuid) -> \(bundleID) source=\(source)")
            return InstalledApp(
                bundleID: bundleID,
                name: bundleID,
                containerPath: fallback.containerPath,
                version: "",
                icon: nil
            )
        }

        if let app = resolvedApp(from: candidates, source: "state/preferences") {
            return app
        }
        if let bundleID = strongCandidates.first {
            return InstalledApp(
                bundleID: bundleID,
                name: bundleID,
                containerPath: fallback.containerPath,
                version: "",
                icon: nil
            )
        }

        let artifactPaths = [
            (libraryPath as NSString).appendingPathComponent("SplashBoard/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Caches/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Cookies"),
            (libraryPath as NSString).appendingPathComponent("WebKit")
        ]
        let artifactNames = artifactPaths.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? []
        }
        let artifactCandidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: [],
            preferenceFileNames: [],
            artifactNames: artifactNames
        )
        if let app = resolvedApp(from: artifactCandidates, source: "artifacts") {
            return app
        }

        let uuid = (fallback.containerPath as NSString).lastPathComponent
        let preview = (candidates + artifactCandidates).prefix(6).joined(separator: ",")
        log("browser: unresolved \(uuid) metadata=unavailable savedStates=\(savedStates.count) preferences=\(preferences.count) artifacts=\(artifactNames.count) candidates=[\(preview)]")
        return nil
    }

    static func inferUnidentifiedApps(
        in apps: [InstalledApp],
        knownApps: [InstalledApp],
        launchServicesIdentifiers: Set<String> = []
    ) -> [InstalledApp] {
        let knownByBundleID = Dictionary(knownApps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        var inferredCount = 0
        let result = apps.enumerated().map { index, app -> InstalledApp in
            guard UUID(uuidString: app.bundleID) != nil,
                  let inferred = autoreleasepool(invoking: {
                      inferredApp(
                        for: app,
                        knownAppsByBundleID: knownByBundleID,
                        launchServicesIdentifiers: launchServicesIdentifiers
                      )
                  }) else {
                return app
            }
            inferredCount += 1
            if inferredCount <= 5 {
                log("browser: inferred \((app.containerPath as NSString).lastPathComponent) -> \(inferred.bundleID)")
            }
            return inferred
        }
        let unresolvedCount = result.filter { UUID(uuidString: $0.bundleID) != nil }.count
        log("browser: inferred identities for \(inferredCount)/\(apps.count) merged containers; unresolved=\(unresolvedCount)")
        return result
    }

    // MARK: File browsing

    static func listFiles(at path: String) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            log("listFiles: FAILED for \(path) errno=\(errno)")
            return []
        }
        var entries: [FileEntry] = []
        for item in items {
            if item.hasPrefix(".") { continue }
            let full = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let size = isDir.boolValue ? 0 : ((try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? 0)
            entries.append(FileEntry(name: item, path: full, isDirectory: isDir.boolValue, size: size))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func readTextFile(at path: String, limit: Int = 200_000) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "Unable to read file."
        }
        let truncated = data.prefix(limit)
        if let text = String(data: truncated, encoding: .utf8) {
            return data.count > limit ? text + "\n… [truncated]" : text
        }
        if let text = String(data: truncated, encoding: .utf16) {
            return data.count > limit ? text + "\n… [truncated]" : text
        }
        return "Binary data (\(data.count) bytes) — not text."
    }
}
