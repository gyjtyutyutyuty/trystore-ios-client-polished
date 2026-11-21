import CryptoKit
import Foundation

struct PatchStoreAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
    var messageArgument: String?

    init(titleKey: String, messageKey: String, messageArgument: String? = nil) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageArgument = messageArgument
    }

    func message(language: AppLanguage) -> String {
        if let messageArgument {
            return language.text(messageKey, messageArgument)
        }
        return language.text(messageKey)
    }
}

enum PatchToggleGroup {
    case aim
    case antena
    case location
}


struct BundledPatch {
    let resourceName: String
    let projectName: String
    let password: String?
}

enum FreeFireGame: Hashable {
    case max

    var bundledPatches: [BundledPatch] {
        [
            BundledPatch(resourceName: "HEAD.TRYSTORE", projectName: "HEAD", password: nil),
            BundledPatch(resourceName: "NECK.TRYSTORE", projectName: "NECK", password: nil),
            BundledPatch(resourceName: "HSPESSCOSO.TRYSTORE", projectName: "HS PESSCOSO", password: nil),
            BundledPatch(resourceName: "HS SLA PECHO.TRYSTORE", projectName: "HS SLA PECHO", password: nil),
            BundledPatch(resourceName: "TryStore.TRYSTORE", projectName: "TryStore", password: nil),
            BundledPatch(resourceName: "HOLOGRAMAEXCLUSIVO.3105", projectName: "HOLOGRAMA EXCLUSIVO", password: nil),
            BundledPatch(resourceName: "Cuello y Drag.TRYSTORE", projectName: "Drag con Cuello", password: nil),
            BundledPatch(resourceName: "Pecho3105.TRYSTORE", projectName: "Pecho3105", password: nil),
            BundledPatch(resourceName: "CUELLO3105.TRYSTORE", projectName: "CUELLO3105", password: nil)
        ]
    }
}

@MainActor
final class PatchProjectStore: ObservableObject {
    @Published private(set) var items: [PatchLibraryItem] = []
    /// Bundle identifiers this device cannot resolve, per package, surfaced in
    /// the library before an apply has a chance to fail.
    @Published private(set) var unavailableTargets: [UUID: [String]] = [:]
    private var availabilityTask: Task<Void, Never>?
    @Published private(set) var isBusy = false
    @Published private(set) var operationProgress: Double = 0
    @Published var passwordRequest: PatchPasswordRequest?
    @Published var alert: PatchStoreAlert?
    @Published var unlockErrorKey: String?

    private struct PendingUnlock {
        let data: Data
        let summary: PatchPackageSummary
        let existingURL: URL?
    }

    private var pendingUnlock: PendingUnlock?
    private let game: FreeFireGame
    private var didInstallRemoteResources = false

    init(game: FreeFireGame = .max) {
        self.game = game
        reload()
    }

    func installBundledResources(credentials: PatchFeedCredentials?) {
        guard !didInstallRemoteResources, !isBusy, let credentials else { return }
        isBusy = true
        Task { [weak self] in
            guard let self else { return }
            do {
                // Packages are wrapped under a key the feed releases only to an
                // authenticated device. Fetch it before decoding, otherwise a
                // cached licence would still leave every package unreadable.
                // Ask on every sync. The feed owns the served key version, so a
                // rotation is otherwise invisible to an install that already
                // holds a key. A transport failure still falls back to the
                // cached key; a rejected licence does not.
                do {
                    try await PatchBundleKeyStore.refresh(
                        licenseKey: credentials.licenseKey,
                        deviceID: credentials.deviceID
                    )
                } catch PatchBundleKeyError.unavailable where PatchBundleKeyStore.cachedKey() != nil {
                    log("patch: bundle key refresh unavailable, using the cached key")
                }
                let resources = try await PatchResourceBundle.load(
                    credentials: credentials,
                    expected: self.game.bundledPatches
                )
                for obsolete in [
                    "HOLOGRAMA ARMAS", "HOLOGRAMA PERSONAJE", "Balas Magicas",
                    "HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO", "EXCLUSIVO AZUL"
                ] {
                    PatchProjectLibrary.removeBundledPackage(named: obsolete)
                }
                var failures: [String] = []
                for patch in self.game.bundledPatches {
                    guard let data = resources[patch.resourceName] else {
                        failures.append(patch.resourceName)
                        continue
                    }
                    let manifestName = URL(fileURLWithPath: patch.resourceName)
                        .deletingPathExtension()
                        .lastPathComponent
                    let installed = PatchProjectLibrary.installRemoteFeedPackageIfNeeded(
                        data,
                        resourceName: patch.resourceName,
                        projectName: patch.projectName,
                        manifestName: manifestName
                    )
                    if !installed {
                        failures.append(patch.resourceName)
                    }
                }
                self.didInstallRemoteResources = failures.isEmpty
                self.reload()
                self.isBusy = false
                if failures.isEmpty {
                    log("patch: authenticated remote sync complete")
                } else {
                    // One package the feed cannot hand over must not fail the
                    // whole library, and "check the link" is the wrong story
                    // when the bytes arrived and only the envelope was wrong.
                    log("patch: authenticated remote sync incomplete: \(failures.joined(separator: ", "))")
                    if failures.count == self.game.bundledPatches.count {
                        self.present(.remoteImportFailed)
                    }
                }
            } catch {
                self.isBusy = false
                self.present(.remoteImportFailed)
                log("patch: authenticated remote patch sync failed: \(error)")
            }
        }
    }

    func reportMissingPackage() {
        alert = PatchStoreAlert(
            titleKey: "patch.status.missing",
            messageKey: "patch.detail.package_missing_long"
        )
    }

    func reload() {
        items = PatchProjectLibrary.load()
        refreshTargetAvailability()
    }

    deinit {
        availabilityTask?.cancel()
    }

    /// Resolution is heavy on iOS 27 (container-manager map plus a metadata
    /// scan), so one task per store runs it off the main actor; a reload cancels
    /// the previous pass instead of stacking another.
    private func refreshTargetAvailability() {
        availabilityTask?.cancel()
        let snapshot: [(UUID, [String])] = items.compactMap { item in
            guard let project = item.project else { return nil }
            return (item.id, project.allBundleIdentifiers)
        }
        guard !snapshot.isEmpty else {
            unavailableTargets = [:]
            return
        }
        availabilityTask = Task.detached(priority: .utility) { [weak self] in
            var missing: [UUID: [String]] = [:]
            for (id, bundleIDs) in snapshot {
                var unresolved: [String] = []
                for bundleID in bundleIDs {
                    if Task.isCancelled { return }
                    if ContainerStore.resolveAppContainerPath(bundleID: bundleID) == nil {
                        unresolved.append(bundleID)
                    }
                }
                if !unresolved.isEmpty { missing[id] = unresolved }
            }
            await MainActor.run { [missing] in
                self?.unavailableTargets = missing
            }
        }
    }

    func create(project: PatchProject, password: String?) {
        runOperation(successMessageKey: "patch.created_message") {
            let encoded = try PatchPackageCodec.encodeNew(project: project, password: password)
            let summary = try PatchPackageCodec.inspect(encoded.data)
            let workspace = try PatchWorkspaceService.createWorkspace(for: project)
            do {
                if summary.isPasswordProtected {
                    try PatchKeyStore.store(encoded.contentKey, for: summary)
                }
                _ = try PatchProjectLibrary.save(data: encoded.data, projectName: project.name)
            } catch {
                try? FileManager.default.removeItem(at: workspace)
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
        }
    }

    func update(project: PatchProject) {
        guard let item = items.first(where: { $0.id == project.id }),
              let contentKey = item.contentKey else {
            present(.invalidProject)
            return
        }
        runOperation(successMessageKey: "patch.updated_message") {
            let original = try PatchProjectLibrary.readPackage(at: item.packageURL)
            let updated = try PatchPackageCodec.update(
                original,
                project: project,
                contentKey: contentKey
            )
            _ = try PatchProjectLibrary.save(
                data: updated,
                projectName: project.name,
                existingURL: item.packageURL
            )
        }
    }

    func requestUnlock(for item: PatchLibraryItem) {
        guard item.isLocked, !isBusy else { return }
        do {
            let data = try PatchProjectLibrary.readPackage(at: item.packageURL)
            pendingUnlock = PendingUnlock(data: data, summary: item.summary, existingURL: item.packageURL)
            passwordRequest = PatchPasswordRequest(summary: item.summary)
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.unsupportedFormat)
        }
    }

    func unlock(password: String) {
        guard let pending = pendingUnlock, !isBusy else { return }
        isBusy = true
        unlockErrorKey = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let decoded = try PatchPackageCodec.decode(pending.data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: pending.summary)
                do {
                    try PatchProjectLibrary.installDeliveredPackage(
                        data: pending.data,
                        decoded: decoded,
                        summary: pending.summary,
                        existingURL: pending.existingURL
                    )
                } catch {
                    try? PatchKeyStore.delete(for: pending.summary)
                    throw error
                }
                await self?.clearPendingUnlock()
                await self?.finishOperation(successMessageKey: "patch.unlocked_message")
            } catch let error as PatchPackageError {
                await self?.failUnlock(error)
            } catch {
                await self?.failUnlock(.invalidPasswordOrCorruptedPackage)
            }
        }
    }

    func cancelUnlock() {
        clearPendingUnlock()
        isBusy = false
    }

    func clearUnlockError() {
        unlockErrorKey = nil
    }

    /// Synchronises a workspace project into its package and returns the URL the
    /// share sheet should present. The library and the detail screen both call
    /// this, so the export path exists once instead of twice.
    func delete(_ item: PatchLibraryItem) {
        do {
            try PatchProjectLibrary.delete(item)
            reload()
        } catch {
            present(.invalidProject)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        for item: PatchLibraryItem,
        group: PatchToggleGroup? = nil,
        reportsSuccess: Bool = true,
        reportsProgress: Bool = false,
        onSuccess: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        guard !isBusy else { return }

        let resolvedGroup = group ?? Self.group(for: item)

        // Reported from the transaction itself, so the bar measures rules
        // written rather than time elapsed. Nil when nobody is watching.
        let reporter: (@Sendable (Int, Int) -> Void)?
        if reportsProgress {
            reporter = { [weak self] done, total in
                guard total > 0 else { return }
                let value = min(1, max(0, Double(done) / Double(total)))
                Task { @MainActor in
                    self?.operationProgress = value
                }
            }
        } else {
            reporter = nil
        }
        if reportsProgress {
            operationProgress = 0
        }

        if enabled {
            guard let baseProject = item.project else {
                present(.invalidProject)
                return
            }

            runOperation(
                successMessageKey: "patch.applied_message",
                reportsSuccess: reportsSuccess,
                onSuccess: { onSuccess?(true) }
            ) {
                log("patch: enabling project=\(baseProject.name) packageID=\(item.id.uuidString) group=\(Self.groupName(resolvedGroup))")
                if let resolvedGroup {
                    let conflictingReceipts = self.items.compactMap { candidate -> (PatchLibraryItem, PatchTransactionReceipt, Date)? in
                        guard candidate.id != item.id,
                              Self.groupsConflict(Self.group(for: candidate), with: resolvedGroup),
                              let receipt = DevicePatchService.latestReceipt(projectID: candidate.id) else {
                            return nil
                        }
                        return (
                            candidate,
                            receipt,
                            PatchTransaction.activationDate(for: receipt) ?? .distantPast
                        )
                    }.sorted { $0.2 > $1.2 }
                    for (candidate, receipt, _) in conflictingReceipts {
                        let candidateName = candidate.project?.name
                            ?? candidate.packageURL.lastPathComponent
                        log("patch: restoring conflicting project=\(candidateName) packageID=\(candidate.id.uuidString) group=\(Self.groupName(resolvedGroup))")
                        do {
                            try DevicePatchService.restore(receipt: receipt, progress: reporter)
                        } catch {
                            // A receipt left behind by an older game build can no
                            // longer verify its container or original digest. It
                            // must not stop the new activation: the package we
                            // are about to write replaces the same target file.
                            log("patch: abandoning stale conflicting project=\(candidateName) packageID=\(candidate.id.uuidString): \(error.localizedDescription)")
                            try? PatchTransaction.abandon(receipt: receipt)
                            DevicePatchService.invalidateReceiptCache()
                        }
                    }
                }

                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                log("patch: activating project=\(project.name) targets=\(project.allBundleIdentifiers.joined(separator: ",")) rules=\(project.rules.count)")
                _ = try DevicePatchService.apply(project: project, progress: reporter)
                guard DevicePatchService.latestReceipt(projectID: item.id) != nil else {
                    log("patch: apply completed without a receipt for packageID=\(item.id.uuidString)")
                    throw PatchPackageError.applyFailed
                }
            }
        } else if let receipt = DevicePatchService.latestReceipt(projectID: item.id) {
            runOperation(
                successMessageKey: "patch.restored_message",
                reportsSuccess: reportsSuccess,
                onSuccess: { onSuccess?(false) }
            ) {
                log("patch: disabling project=\(item.project?.name ?? item.packageURL.lastPathComponent) packageID=\(item.id.uuidString)")
                try DevicePatchService.restore(receipt: receipt, progress: reporter)
            }
        }
    }

    private static func group(for item: PatchLibraryItem) -> PatchToggleGroup? {
        let name = item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent
        switch name {
        case "HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO", "BALAS":
            return .aim
        case "TryStore", "Balas Magicas", "Drag con Cuello", "Aimbot Pecho", "Pecho3105", "CUELLO3105":
            return .antena
        case "HOLOGRAMA EXCLUSIVO", "HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO", "ARMAS", "EXCLUSIVO AZUL":
            return .location
        default:
            return nil
        }
    }

    private static func groupsConflict(_ candidateGroup: PatchToggleGroup?, with requestedGroup: PatchToggleGroup) -> Bool {
        guard let candidateGroup else { return false }
        switch (candidateGroup, requestedGroup) {
        case (.aim, .aim), (.aim, .antena), (.antena, .aim), (.antena, .antena), (.location, .location):
            // Aim and Antena bundles both replace the same Free Fire assetindexer file.
            return true
        default:
            return false
        }
    }

    private static func groupName(_ group: PatchToggleGroup?) -> String {
        guard let group else { return "none" }
        switch group {
        case .aim: return "aim"
        case .antena: return "antena"
        case .location: return "location"
        }
    }

    func synchronizeWorkspace(projectID: UUID, reportsSuccess: Bool = false) {
        guard let item = items.first(where: { $0.id == projectID }),
              item.summary.schemaVersion >= 2,
              !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                await self?.finishWorkspaceSynchronization(reportsSuccess: reportsSuccess)
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.invalidProject)
            }
        }
    }

    private func finishWorkspaceSynchronization(reportsSuccess: Bool) {
        reload()
        isBusy = false
        if reportsSuccess {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.workspace_synced_message"
            )
        }
    }

    private func runOperation(
        successMessageKey: String,
        reportsSuccess: Bool = true,
        onSuccess: (@MainActor @Sendable () -> Void)? = nil,
        operation: @escaping () throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                log("patch: operation started")
                try operation()
                if let self {
                    await self.finishOperation(
                        successMessageKey: successMessageKey,
                        reportsSuccess: reportsSuccess
                    )
                    await onSuccess?()
                }
            } catch let error as PatchPackageError {
                log("patch: operation failed: \(error.localizedDescription)")
                await self?.failOperation(error)
            } catch {
                log("patch: unexpected operation failure: \(error.localizedDescription)")
                await self?.failOperation(.invalidProject)
            }
        }
    }

    private func clearPendingUnlock() {
        pendingUnlock = nil
        passwordRequest = nil
        unlockErrorKey = nil
    }

    private func finishOperation(successMessageKey: String, reportsSuccess: Bool = true) {
        reload()
        operationProgress = 1
        isBusy = false
        alert = reportsSuccess
            ? PatchStoreAlert(titleKey: "common.done", messageKey: successMessageKey)
            : nil
    }

    private func failOperation(_ error: PatchPackageError) {
        operationProgress = 1
        isBusy = false
        present(error)
    }

    private func failUnlock(_ error: PatchPackageError) {
        isBusy = false
        // Keep the password sheet open so the user can retry.
        // Presenting an alert while dismissing the sheet swallows the message.
        if case .invalidPasswordOrCorruptedPackage = error {
            unlockErrorKey = "patch.error.wrong_password"
        } else {
            unlockErrorKey = error.localizationKey
        }
    }

    private func present(_ error: PatchPackageError) {
        alert = PatchStoreAlert(
            titleKey: "common.failed",
            messageKey: error.localizationKey,
            messageArgument: error.localizationArgument
        )
    }
}
