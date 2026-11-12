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
            BundledPatch(resourceName: "EXCLUSIVO AZUL.TRYSTORE", projectName: "EXCLUSIVO AZUL", password: nil),
            BundledPatch(resourceName: "TryStore.TRYSTORE", projectName: "TryStore", password: nil),
            BundledPatch(resourceName: "HOLOGRAMAEXCLUSIVO(4).TRYSTORE", projectName: "HOLOGRAMA EXCLUSIVO VERDE", password: nil),
            BundledPatch(resourceName: "HOLOGRAMAEXCLUSIVO(5).TRYSTORE", projectName: "HOLOGRAMA EXCLUSIVO ROSADO", password: nil),
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
                if PatchBundleKeyStore.cachedKey() == nil {
                    try await PatchBundleKeyStore.refresh(
                        licenseKey: credentials.licenseKey,
                        deviceID: credentials.deviceID
                    )
                }
                let resources = try await PatchResourceBundle.load(
                    credentials: credentials,
                    expected: self.game.bundledPatches
                )
                for obsolete in ["HOLOGRAMA ARMAS", "HOLOGRAMA PERSONAJE", "Balas Magicas"] {
                    PatchProjectLibrary.removeBundledPackage(named: obsolete)
                }
                var failures: [String] = []
                for patch in self.game.bundledPatches {
                    guard let data = resources[patch.resourceName] else {
                        failures.append(patch.resourceName)
                        continue
                    }
                    let installed = PatchProjectLibrary.installRemoteFeedPackageIfNeeded(
                        data,
                        resourceName: patch.resourceName,
                        projectName: patch.projectName,
                        manifestName: patch.resourceName.replacingOccurrences(of: ".TRYSTORE", with: "")
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
                    log("patch: authenticated remote sync incomplete: \(failures.joined(separator: ", "))")
                    self.present(.remoteImportFailed)
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
            await MainActor.run {
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

    func importPackage(
        at sourceURL: URL,
        reportsSuccess: Bool = true,
        completion: (@MainActor @Sendable (String?) -> Void)? = nil
    ) {
        guard !isBusy else {
            completion?("Another patch operation is already running.")
            return
        }
        isBusy = true
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try PatchProjectLibrary.readPackage(at: sourceURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                ) {
                    await self?.requestPassword(pending: pending)
                    await completion?("The remote package requires a password.")
                } else {
                    await self?.finishOperation(
                        successMessageKey: "patch.imported_message",
                        reportsSuccess: reportsSuccess
                    )
                    await completion?(nil)
                }
            } catch let error as PatchPackageError {
                log("patch: import failed: \(error.localizedDescription)")
                await self?.failOperation(error)
                await completion?(error.localizedDescription)
            } catch {
                log("patch: import failed: \(error.localizedDescription)")
                await self?.failOperation(.unsupportedFormat)
                await completion?(error.localizedDescription)
            }
        }
    }

    func importPackage(from source: PatchImportSource, credentials: PatchFeedCredentials? = nil) {
        switch source {
        case .file(let url):
            importPackage(at: url)
        case .remote(let url):
            importPackage(fromRemoteURL: url, credentials: credentials)
        case .invalid:
            present(.invalidImportLink)
        }
    }


    private func importPackage(fromRemoteURL remoteURL: URL, credentials: PatchFeedCredentials?) {
        guard !isBusy,
              PatchImportRoute.validatedRemoteURL(remoteURL) != nil else {
            if !isBusy { present(.invalidImportLink) }
            return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let requiresFeedAuth = remoteURL.host?.lowercased() == "trystore-patch-feed.burgoajustin.workers.dev"
                    && remoteURL.path.hasPrefix("/patches/trystore/")
                var request = URLRequest(url: remoteURL)
                if requiresFeedAuth {
                    guard let credentials else { throw PatchPackageError.remoteImportFailed }
                    request.setValue("Bearer \(credentials.licenseKey)", forHTTPHeaderField: "Authorization")
                    request.setValue(credentials.deviceID, forHTTPHeaderField: "X-TryStore-Device-ID")
                    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }

                let (temporaryURL, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let finalURL = response.url,
                      (!requiresFeedAuth || finalURL.host?.lowercased() == remoteURL.host?.lowercased()),
                      PatchImportRoute.validatedRemoteURL(finalURL) != nil else {
                    throw PatchPackageError.remoteImportFailed
                }

                let data = try PatchProjectLibrary.readPackage(at: temporaryURL)
                if requiresFeedAuth {
                    let expectedDigest = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "v" })?.value
                    let actualDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard let expectedDigest, expectedDigest.count == 64,
                          actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                        throw PatchPackageError.remoteImportFailed
                    }
                }
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                ) {
                    await self?.requestPassword(pending: pending)
                } else {
                    await self?.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.remoteImportFailed)
            }
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
                    try PatchProjectLibrary.installImportedPackage(
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
                        log("patch: restoring conflicting project=\(candidate.project?.name ?? candidate.packageURL.lastPathComponent) packageID=\(candidate.id.uuidString) group=\(Self.groupName(resolvedGroup))")
                        try DevicePatchService.restore(receipt: receipt, progress: reporter)
                    }
                }

                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project, progress: reporter)
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
        case "HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO", "ARMAS", "EXCLUSIVO AZUL":
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

    private func requestPassword(pending: PendingUnlock) {
        pendingUnlock = pending
        passwordRequest = PatchPasswordRequest(summary: pending.summary)
        isBusy = false
    }

    private func existingPackageURL(for packageID: UUID) -> URL? {
        items.first(where: { $0.id == packageID })?.packageURL
    }

    private nonisolated static func persistImportedPackage(
        data: Data,
        summary: PatchPackageSummary,
        existingURL: URL?
    ) throws -> PendingUnlock? {
        if let key = try PatchKeyStore.load(for: summary) {
            let decoded = try PatchPackageCodec.decode(data, contentKey: key)
            try PatchProjectLibrary.installImportedPackage(
                data: data,
                decoded: decoded,
                summary: summary,
                existingURL: existingURL
            )
            return nil
        }
        if summary.isPasswordProtected {
            return PendingUnlock(data: data, summary: summary, existingURL: existingURL)
        }
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        try PatchProjectLibrary.installImportedPackage(
            data: data,
            decoded: decoded,
            summary: summary,
            existingURL: existingURL
        )
        return nil
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
