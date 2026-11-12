import Foundation

enum DevicePatchService {
    /// `latestReceipt` is read from every patch card and every bus segment on
    /// each SwiftUI pass. A cold read enumerates the backup tree and parses a
    /// journal per transaction, so the answer is cached until an apply or
    /// restore invalidates it.
    private static var receiptCache: [UUID: PatchTransactionReceipt?] = [:]
    private static let receiptCacheLock = NSLock()

    static func apply(
        project: PatchProject,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> PatchTransactionReceipt {
        defer { invalidateReceiptCache() }
        try requireAppGroupIfNeeded()
        let bundleIDs = orderedBundleIdentifiers(in: project)
        let useTunnel = usesPairingTunnel
        log("patch: apply route \(useTunnel ? "pairing tunnel" : "local sandbox")")
        if useTunnel {
            let context = try pairingRemoteContext(bundleIDs: bundleIDs)
            return try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = context.roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                progress: progress,
                remoteWriter: pairingRemoteWriter(context: context),
                remoteReader: pairingRemoteReader(context: context)
            )
        }
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                progress: progress
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws {
        defer { invalidateReceiptCache() }
        try requireAppGroupIfNeeded()
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        let useTunnel = usesPairingTunnel
        log("patch: restore route \(useTunnel ? "pairing tunnel" : "local sandbox")")
        if useTunnel {
            let context = try pairingRemoteContext(bundleIDs: bundleIDs)
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = context.roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                remoteWriter: pairingRemoteWriter(context: context),
                remoteReader: pairingRemoteReader(context: context),
                progress: progress
            )
            return
        }
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                progress: progress
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        receiptCacheLock.lock()
        if let cached = receiptCache[projectID] {
            receiptCacheLock.unlock()
            return cached
        }
        receiptCacheLock.unlock()

        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else {
            receiptCacheLock.lock()
            receiptCache.updateValue(nil, forKey: projectID)
            receiptCacheLock.unlock()
            return nil
        }
        let receipt = PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
        receiptCacheLock.lock()
        receiptCache.updateValue(receipt, forKey: projectID)
        receiptCacheLock.unlock()
        return receipt
    }

    static func invalidateReceiptCache() {
        receiptCacheLock.lock()
        receiptCache.removeAll(keepingCapacity: true)
        receiptCacheLock.unlock()
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    /// Local writes need a working backend. 18.7.2 and later have no kernel
    /// chain, and 26.7+/27 lose worse_query when the signing profile carries no
    /// App Group, so those builds go over the pairing tunnel instead — the
    /// tunnel is build-agnostic and was how they patched before.
    ///
    /// The kernel and bad_query builds never take this branch: a failed kernel
    /// probe there means the exploit has not run yet, not that the tunnel is
    /// the next step, and the transaction reports that failure itself.
    static var usesPairingTunnel: Bool {
        let version = AppInfo.versionTuple
        let tunnelSupported = ExploitSupportPolicy.supportsPairingTunnel(
            major: version.major,
            minor: version.minor,
            patch: version.patch
        )
        switch SandboxAccess.backend {
        case .kernel, .badQuery:
            return false
        case .worseQuery:
            // iOS 27 patches only run locally; a failed probe is reported as a
            // missing App Group, never as a reason to open the tunnel.
            return false
        case .unsupported:
            return tunnelSupported
        }
    }

    /// worse_query cannot start without the App Group the signer must carry,
    /// and a signed group still fails when the escape itself cannot probe.
    /// Both are reported before any container lookup, with different errors.
    private static func requireAppGroupIfNeeded() throws {
        guard SandboxAccess.backend == .worseQuery else { return }
        guard SandboxAccess.hasAppGroup else {
            log("patch: worse_query blocked — no App Group entitlement in the signed profile")
            throw PatchPackageError.appGroupMissing
        }
        guard SandboxAccess.probe() else {
            log("patch: worse_query blocked — App Group present but the probe failed")
            throw PatchPackageError.worseQueryUnavailable
        }
        log("patch: worse_query probe passed on \(SandboxAccess.appGroup ?? "the App Group")")
    }

    private struct PairingRemoteContext {
        let pairingFileURL: URL
        let roots: [String: URL]
        let containerPaths: [String: String]
    }

    private static func pairingRemoteContext(bundleIDs: [String]) throws -> PairingRemoteContext {
        guard LocalDevTunnelProbe.isConnected else {
            throw PatchPackageError.pairingTunnelRequired
        }
        let pairingFileURL = PairingController.pairingFileURL
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            throw AppInfo.versionTuple.major >= 27
                ? PatchPackageError.pairingFileMissing
                : PatchPackageError.pairingFileImportRequired
        }

        var roots: [String: URL] = [:]
        var containerPaths: [String: String] = [:]
        for bundleID in bundleIDs {
            let path: String
            do {
                path = try PairingTunnelService.remoteContainerPath(
                    pairingFileURL: pairingFileURL,
                    bundleID: bundleID
                )
            } catch {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            guard ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            containerPaths[bundleID] = path
            roots[bundleID] = PatchPathValidator.canonicalFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            )
            log("patch: Airlift resolved app container \(bundleID)")
        }
        return PairingRemoteContext(
            pairingFileURL: pairingFileURL,
            roots: roots,
            containerPaths: containerPaths
        )
    }

    private static func pairingRemoteWriter(
        context: PairingRemoteContext
    ) -> PatchTransaction.RemoteWriter {
        return { bundleID, relativePath, data in
            guard let remoteContainer = context.containerPaths[bundleID] else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            try PairingTunnelService.writeFile(
                bundleID: bundleID,
                relativePath: relativePath,
                data: data,
                pairingFileURL: context.pairingFileURL,
                remoteContainerPath: remoteContainer
            )
        }
    }

    private static func pairingRemoteReader(
        context: PairingRemoteContext
    ) -> PatchTransaction.RemoteReader {
        return { bundleID, relativePath in
            guard let remoteContainer = context.containerPaths[bundleID] else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            return try PairingTunnelService.readFile(
                bundleID: bundleID,
                relativePath: relativePath,
                pairingFileURL: context.pairingFileURL,
                remoteContainerPath: remoteContainer
            )
        }
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var grants: [Int64] = []
        defer {
            for grant in grants { SandboxAccess.release(grant) }
        }

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            // Held for the whole transaction: releasing before the write or the
            // read-back would revoke access on worse_query.
            let grant = ContainerStore.grantContainerAccess(path)
            log("patch: container grant \(bundleID) -> \(grant)")
            if grant >= 0 { grants.append(grant) }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
