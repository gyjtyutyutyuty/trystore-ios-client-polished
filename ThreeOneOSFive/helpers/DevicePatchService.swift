import Foundation

enum DevicePatchService {
    /// Applies the project currently stored in the local Store.
    /// Workspace projects are snapshotted immediately before patching so Home
    /// cannot apply an older in-memory copy after a Files edit.
    static func apply(item: PatchLibraryItem) throws -> PatchTransactionReceipt {
        let project: PatchProject
        if item.summary.schemaVersion >= 2 {
            project = try PatchProjectLibrary.synchronizeWorkspace(item: item)
        } else {
            guard let storedProject = item.project else {
                throw PatchPackageError.invalidProject
            }
            project = storedProject
        }
        return try apply(project: project)
    }

    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(receipt: PatchTransactionReceipt) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restoreAllExistingReceipts() -> Int {
        let items = PatchProjectLibrary.load()
        var restored = 0
        for item in items {
            guard let receipt = latestReceipt(projectID: item.id) else { continue }
            do {
                try restore(receipt: receipt)
                restored += 1
            } catch {
                log("patch: launch reconciliation failed for \(item.packageURL.lastPathComponent): \(error)")
            }
        }
        return restored
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
