import Foundation

/// Applies and restores patch transactions against containers this process can
/// reach directly.
///
/// Every target bundle is resolved before the transaction starts, so a project
/// that names an app outside the sandbox fails with `targetAppUnavailable`
/// rather than half-applying. There is no pairing-tunnel or remote writer
/// branch: the transaction writes through the same `FileManager`-based path as
/// the file workspace.
enum DevicePatchService {
    static func apply(
        project: PatchProject,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> PatchTransactionReceipt {
        return try withResolvedContainers(bundleIDs: orderedBundleIdentifiers(in: project)) { roots in
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
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
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
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
