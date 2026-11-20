import Foundation
import CryptoKit

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var project: PatchProject?
    var contentKey: Data?
    var packageURL: URL

    var id: UUID { summary.packageID }
    var isLocked: Bool { project == nil }
    var workspaceURL: URL? {
        PatchWorkspaceService.workspaceURL(projectID: id)
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

enum PatchProjectLibrary {
    private static let bundledProjectIDs: [String: UUID] = [
        "HOLOGRAMA EXCLUSIVO VERDE": UUID(uuidString: "B1672AC3-AE42-4A0A-9A11-02A54C2C8F10")!,
        "HOLOGRAMA EXCLUSIVO ROSADO": UUID(uuidString: "2E5D8A71-3C4B-4F92-8D6A-7715C8E34B20")!
    ]
    private static let supportedPackageExtensions: Set<String> = ["trystore", "3105"]
    private static let bundledProjectNames: Set<String> = [
        "HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO", "EXCLUSIVO AZUL", "TryStore", "Balas Magicas",
        "HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO", "Drag con Cuello",
        "Pecho3105", "CUELLO3105"
    ]
    /// Payload fingerprints for the canonical packages. They are not secret:
    /// they let a device refuse a local package whose rules were swapped or
    /// edited, even before the signed feed has a chance to repair it. A feed
    /// install overwrites the stored fingerprint with the payload it delivered.
    private static let bundledPayloadFingerprints: [UUID: String] = [
        UUID(uuidString: "668D6990-D407-439F-8846-2AC6E03498BA")!: "ad023df96e09a81fe4b5a776a2396b449f300a8ee4c6037874f00ef2d726ede4",
        UUID(uuidString: "74028F92-DE35-43F0-8E40-423D10EE3D42")!: "82afb625c0a319127a607934e509bd7448efa82246cab13ef274fe27555f0504",
        UUID(uuidString: "6E3DE2CA-1F8D-435F-A366-7692994D0094")!: "a55fb498b7bfc0e785c556a22f56637d5471ab225f09e88ed461057707a14eed",
        UUID(uuidString: "6A510E8A-A467-48D3-B81D-7B6E482FEFCB")!: "89fb8543ed57a68e3ef3985d0fb7769de572e7b2fb8066e0d8391732683a4ef4",
        UUID(uuidString: "1B7B4E1F-027B-4747-A933-2F545DC19DE2")!: "3639ef703b2a87685ebb5283eb41c4464d7c018b2534748383ecd13cca398563",
        UUID(uuidString: "42CE925C-05DF-4D95-8DE0-E229BE02E599")!: "8e7468115ee151bda82c24f4985ccfe85252da923e43ff1945703392c59cea21",
        UUID(uuidString: "B1672AC3-AE42-4A0A-9A11-02A54C2C8F10")!: "98e854db4cbb76daba25dbf868de35c2ae30151ae64a49f3ef7ab5b2856ab362",
        UUID(uuidString: "2E5D8A71-3C4B-4F92-8D6A-7715C8E34B20")!: "9a3692209ec509547dff9f642416fd329ad46478ed47f54f2b9d91b484c0dead",
        UUID(uuidString: "730F4929-EAF2-47D8-8EC1-39210322E46F")!: "326b4f3c99fdcb8968aef964db942ef557a3ac070c26fe91111416c524754291",
        UUID(uuidString: "68F2ACB2-2464-4CC3-ABFA-30D29077A81B")!: "e8fa800ae6ed75ceb8b3c13aa234775017c30a28d7ed025910d0a9423f0cba47",
        UUID(uuidString: "0F13736C-D7A2-4E02-AC21-40DFC8463F89")!: "d6545ed17594911430e378a28d6c81c07057517c6a2f5f682355e2e62aeb11e2"
    ]

    private static let canonicalBundledPackageFilenames: [UUID: String] = [
        UUID(uuidString: "668D6990-D407-439F-8846-2AC6E03498BA")!: "HEAD.TRYSTORE",
        UUID(uuidString: "74028F92-DE35-43F0-8E40-423D10EE3D42")!: "NECK.TRYSTORE",
        UUID(uuidString: "6E3DE2CA-1F8D-435F-A366-7692994D0094")!: "HS PESSCOSO.TRYSTORE",
        UUID(uuidString: "6A510E8A-A467-48D3-B81D-7B6E482FEFCB")!: "HS SLA PECHO.TRYSTORE",
        UUID(uuidString: "1B7B4E1F-027B-4747-A933-2F545DC19DE2")!: "EXCLUSIVO AZUL.TRYSTORE",
        UUID(uuidString: "42CE925C-05DF-4D95-8DE0-E229BE02E599")!: "TryStore.TRYSTORE",
        UUID(uuidString: "B1672AC3-AE42-4A0A-9A11-02A54C2C8F10")!: "HOLOGRAMA EXCLUSIVO VERDE.TRYSTORE",
        UUID(uuidString: "2E5D8A71-3C4B-4F92-8D6A-7715C8E34B20")!: "HOLOGRAMA EXCLUSIVO ROSADO.TRYSTORE",
        UUID(uuidString: "730F4929-EAF2-47D8-8EC1-39210322E46F")!: "Drag con Cuello.TRYSTORE",
        UUID(uuidString: "68F2ACB2-2464-4CC3-ABFA-30D29077A81B")!: "Pecho3105.TRYSTORE",
        UUID(uuidString: "0F13736C-D7A2-4E02-AC21-40DFC8463F89")!: "CUELLO3105.TRYSTORE"
    ]

    private static let legacyRemoteProjectNames: [String: String] = [
        "HOLOGRAMAEXCLUSIVO(4).TRYSTORE": "HOLOGRAMA EXCLUSIVO VERDE",
        "HOLOGRAMAEXCLUSIVO(5).TRYSTORE": "HOLOGRAMA EXCLUSIVO ROSADO"
    ]

    private static let remoteFeedProjectNames: [String: String] = [
        "HSPESSCOSO.TRYSTORE": "HS PESSCOSO",
        "Cuello y Drag.TRYSTORE": "Drag con Cuello",
        "Pecho3105.TRYSTORE": "Aimbot Pecho",
        "CUELLO3105.TRYSTORE": "Aimbot Pecho"
    ]

    static func legacyRemoteProjectName(for fileName: String) -> String? {
        legacyRemoteProjectNames[fileName]
    }

    static func remoteFeedIdentityMatches(
        expectedManifestName: String,
        fileName: String,
        actualProjectName: String
    ) -> Bool {
        if projectNameMatches(expected: expectedManifestName, actual: actualProjectName) {
            return true
        }

        let fileStem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        guard projectNameMatches(expected: expectedManifestName, actual: fileStem) else {
            return false
        }

        if let legacyProjectName = legacyRemoteProjectNames[fileName] {
            return projectNameMatches(expected: legacyProjectName, actual: actualProjectName)
                || projectNameMatches(expected: "HOLOGRAMA EXCLUSIVO", actual: actualProjectName)
        }
        guard let expectedProjectName = remoteFeedProjectNames[fileName] else {
            return false
        }
        return projectNameMatches(expected: expectedProjectName, actual: actualProjectName)
    }

    /// Only the two known historical visual packages may use the schema-9
    /// bundled migration path. Re-encode them as current schema-2 packages
    /// before passing them through the normal remote import pipeline.
    static func normalizeRemoteFeedPackage(_ data: Data, fileName: String) throws -> Data {
        do {
            _ = try PatchPackageCodec.inspect(data)
            return data
        } catch PatchPackageError.unsupportedVersion {
            guard let projectName = legacyRemoteProjectNames[fileName],
                  let projectID = bundledProjectIDs[projectName] else {
                throw PatchPackageError.unsupportedVersion
            }

            let source = try PatchPackageCodec.decodeBundledResource(data)
            guard source.summary.schemaVersion == 9 else {
                throw PatchPackageError.unsupportedVersion
            }

            var project = source.decoded.project
            project.name = projectName
            project.id = projectID
            return try PatchPackageCodec.encodeNew(project: project, password: nil).data
        }
    }

    /// Decodes a feed package in any format the feed has shipped: the current
    /// envelope, a bundle-wrapped one that only the fetched feed key can open,
    /// and the legacy schema-9 envelopes. Identity is verified before the
    /// project is renamed, so accepting more envelopes cannot accept a
    /// different patch than the one the manifest announced.
    private static func decodeRemoteFeedPackage(
        _ sourceData: Data,
        resourceName: String
    ) throws -> (data: Data, decoded: DecodedPatchPackage) {
        if let normalized = try? normalizeRemoteFeedPackage(sourceData, fileName: resourceName),
           let summary = try? PatchPackageCodec.inspect(normalized),
           !summary.isPasswordProtected,
           let decoded = try? PatchPackageCodec.decode(normalized, password: nil) {
            return (normalized, decoded)
        }

        // The feed wraps a few visual patches with the bundle key. inspect()
        // accepts the envelope but decode(password: nil) cannot open it, which
        // used to drop the whole sync with invalidPasswordOrCorruptedPackage.
        // The payload keeps its own name here; the caller checks it against the
        // manifest and only then renames the project.
        guard let bundled = try? PatchPackageCodec.decodeBundledResource(sourceData) else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }

        let encoded = try PatchPackageCodec.encodeNew(project: bundled.decoded.project, password: nil)
        guard let summary = try? PatchPackageCodec.inspect(encoded.data),
              !summary.isPasswordProtected,
              let decoded = try? PatchPackageCodec.decode(encoded.data, password: nil) else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        log("patch: recovered bundle-wrapped feed package: \(resourceName)")
        return (encoded.data, decoded)
    }

    static func isBundledProject(_ project: PatchProject) -> Bool {
        bundledProjectNames.contains(project.name)
    }

    static func projectNameMatches(expected: String, actual: String) -> Bool {
        let expectedKey = normalizedProjectName(expected)
        let actualKey = normalizedProjectName(actual)
        if expectedKey == actualKey { return true }
        return (expectedKey == "trystore" && actualKey == "balasmagicas")
            || (expectedKey == "exclusivoazul" && actualKey == "hologramaarmas")
            || (expectedKey == "hologramaexclusivoverde" && actualKey == "hologramaexclusivo")
            || (expectedKey == "hologramaexclusivorosado" && actualKey == "hologramaexclusivo")
            || (expectedKey == "pecho3105" && actualKey == "aimbotpecho")
            || (expectedKey == "cuello3105" && actualKey == "aimbotpecho")
    }

    private static func normalizedProjectName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func removeBundledPackage(named projectName: String, fileManager: FileManager = .default) {
        guard let root = try? packageRootURL(fileManager: fileManager) else { return }
        for extensionName in ["TRYSTORE", "3105"] {
            let destination = root.appendingPathComponent("\(projectName).\(extensionName)")
            try? fileManager.removeItem(at: destination)
        }
    }

    static func installBundledPackageIfNeeded(
        resourceName: String,
        projectName: String? = nil,
        password: String? = "nmkiosvn",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
          guard let asset = NSDataAsset(name: resourceName, bundle: bundle),
              let sourceData = try? Data(asset.data),
              let sourceSummary = try? PatchPackageCodec.inspect(sourceData),
              let root = try? packageRootURL(fileManager: fileManager) else { return }

        let packageName = projectName ?? resourceName
        let destination = root.appendingPathComponent("\(packageName).TRYSTORE")
        if fileManager.fileExists(atPath: destination.path) {
            if let existingData = try? readPackage(at: destination),
               let existingSummary = try? PatchPackageCodec.inspect(existingData),
               existingSummary.isPasswordProtected,
               let keyResult = try? PatchKeyStore.load(for: existingSummary),
               let existingDecoded = try? PatchPackageCodec.decode(existingData, contentKey: keyResult),
               existingDecoded.project.name == packageName {
                if let expectedID = bundledProjectIDs[packageName], existingDecoded.project.id != expectedID {
                    try? PatchKeyStore.delete(for: existingSummary)
                    try? PatchWorkspaceService.deleteWorkspace(
                        projectID: existingDecoded.project.id,
                        fileManager: fileManager
                    )
                    try? fileManager.removeItem(at: destination)
                } else {
                    if isBundledProject(existingDecoded.project) {
                        try? PatchWorkspaceService.deleteWorkspace(
                            projectID: existingDecoded.project.id,
                            fileManager: fileManager
                        )
                    }
                    return
                }
            }
            try? fileManager.removeItem(at: destination)
        }

        let decoded: DecodedPatchPackage?
        if let current = try? PatchPackageCodec.decode(sourceData, password: password) {
            decoded = current
        } else if password != "YaBao",
                  let legacy = try? PatchPackageCodec.decode(sourceData, password: "YaBao") {
            decoded = legacy
        } else if !sourceSummary.isPasswordProtected,
                  let unprotected = try? PatchPackageCodec.decode(sourceData, password: nil) {
            decoded = unprotected
        } else {
            decoded = nil
        }
        guard let decoded else { return }

        var normalizedProject = decoded.project
        normalizedProject.name = packageName
        if let bundledProjectID = bundledProjectIDs[packageName] {
            normalizedProject.id = bundledProjectID
        }
        guard let encoded = try? PatchPackageCodec.encodeNew(
            project: normalizedProject,
            password: password
        ), let summary = try? PatchPackageCodec.inspect(encoded.data) else { return }

        do {
            try PatchKeyStore.store(encoded.contentKey, for: summary)
            let savedURL = try save(
                data: encoded.data,
                projectName: packageName,
                fileManager: fileManager
            )
            try installDeliveredPackage(
                data: encoded.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: encoded.contentKey),
                summary: summary,
                existingURL: savedURL,
                createWorkspace: false,
                fileManager: fileManager
            )
            if savedURL != destination {
                try? fileManager.moveItem(at: savedURL, to: destination)
            }
        } catch {
            log("patch: bundled package unavailable")
        }
    }

    @discardableResult
    static func installBundledPackageDataIfNeeded(
        _ sourceData: Data,
        projectName: String,
        password: String? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let source = try? PatchPackageCodec.decodeBundledResource(sourceData) else {
            log("patch: bundled package decode failed: \(projectName)")
            return false
        }
        guard projectNameMatches(expected: projectName, actual: source.decoded.project.name) else {
            log("patch: bundled package identity mismatch: expected \(projectName), payload \(source.decoded.project.name)")
            return false
        }
        guard let root = try? packageRootURL(fileManager: fileManager) else {
            log("patch: bundled package storage unavailable: \(projectName)")
            return false
        }

        let destination = root.appendingPathComponent("\(projectName).TRYSTORE")
        let sourceRevision = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        let revisionKey = "patch.bundledPackageRevision.\(normalizedProjectName(projectName))"
        if fileManager.fileExists(atPath: destination.path) {
            if let existingData = try? readPackage(at: destination),
               let existingSummary = try? PatchPackageCodec.inspect(existingData),
               let key = try? PatchKeyStore.load(for: existingSummary),
               let existingDecoded = try? PatchPackageCodec.decode(existingData, contentKey: key),
               existingDecoded.project.name == projectName {
                let expectedID = bundledProjectIDs[projectName] ?? source.decoded.project.id
                if existingDecoded.project.id == expectedID,
                   UserDefaults.standard.string(forKey: revisionKey) == sourceRevision {
                    return true
                }
                try? PatchKeyStore.delete(for: existingSummary)
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: existingDecoded.project.id,
                    fileManager: fileManager
                )
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
        }

        do {
            var normalizedProject = source.decoded.project
            normalizedProject.name = projectName
            if let bundledProjectID = bundledProjectIDs[projectName] {
                normalizedProject.id = bundledProjectID
            }
            let normalizedData = try PatchPackageCodec.encodeNew(
                project: normalizedProject,
                password: password
            )
            let normalizedSummary = try PatchPackageCodec.inspect(normalizedData.data)
            try PatchKeyStore.store(normalizedData.contentKey, for: normalizedSummary)
            try installDeliveredPackage(
                data: normalizedData.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: normalizedData.contentKey),
                summary: normalizedSummary,
                existingURL: nil,
                createWorkspace: false,
                fileManager: fileManager
            )
            UserDefaults.standard.set(sourceRevision, forKey: revisionKey)
            log("patch: installed IPA-bundled snapshot: \(projectName)")
            return true
        } catch {
            log("patch: bundled file install failed: \(projectName) — \(error)")
            return false
        }
    }

    @discardableResult
    static func installRemoteFeedPackageIfNeeded(
        _ sourceData: Data,
        resourceName: String,
        projectName: String,
        manifestName: String,
        fileManager: FileManager = .default
    ) -> Bool {
        do {
            let expectedID = canonicalBundledPackageFilenames.first {
                URL(fileURLWithPath: $0.value).deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare(projectName) == .orderedSame
            }?.key
            guard let expectedID else { return false }

            let feedPackage = try decodeRemoteFeedPackage(
                sourceData,
                resourceName: resourceName
            ).decoded
            guard remoteFeedIdentityMatches(
                expectedManifestName: manifestName,
                fileName: resourceName,
                actualProjectName: feedPackage.project.name
            ) else {
                log("patch: remote package identity mismatch: \(resourceName)")
                return false
            }

            guard let root = try? packageRootURL(fileManager: fileManager) else { return false }
            let canonicalFilename = canonicalBundledPackageFilenames[expectedID] ?? "\(projectName).TRYSTORE"
            let destination = root.appendingPathComponent(canonicalFilename)

            var normalizedProject = feedPackage.project
            normalizedProject.name = projectName
            normalizedProject.id = expectedID
            let feedFingerprint = projectPayloadFingerprint(normalizedProject)
            if let existingData = try? readPackage(at: destination),
               let existingSummary = try? PatchPackageCodec.inspect(existingData),
               existingSummary.packageID == expectedID,
               !existingSummary.isPasswordProtected,
               let existingPackage = try? PatchPackageCodec.decode(existingData, password: nil),
               projectPayloadFingerprint(existingPackage.project) == feedFingerprint {
                UserDefaults.standard.set(
                    hexString(feedFingerprint),
                    forKey: trustedPayloadKey(expectedID)
                )
                removeDuplicatePackages(
                    packageID: expectedID,
                    keeping: destination,
                    in: root,
                    fileManager: fileManager
                )
                return true
            }

            let encoded = try PatchPackageCodec.encodeNew(project: normalizedProject, password: nil)
            let summary = try PatchPackageCodec.inspect(encoded.data)
            guard summary.packageID == expectedID, !summary.isPasswordProtected else { return false }
            if let existingSummary = try? PatchPackageCodec.inspect(readPackage(at: destination)) {
                try? PatchKeyStore.delete(for: existingSummary)
            }
            try installDeliveredPackage(
                data: encoded.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: encoded.contentKey),
                summary: summary,
                existingURL: destination,
                createWorkspace: false,
                fileManager: fileManager
            )
            UserDefaults.standard.set(
                hexString(projectPayloadFingerprint(normalizedProject)),
                forKey: trustedPayloadKey(expectedID)
            )
            removeDuplicatePackages(
                packageID: expectedID,
                keeping: destination,
                in: root,
                fileManager: fileManager
            )
            log("patch: installed authenticated remote package: \(projectName)")
            return true
        } catch {
            log("patch: remote package install failed: \(resourceName) — \(error)")
            return false
        }
    }

    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        guard let root = try? packageRootURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else { return [] }

        var byID: [UUID: PatchLibraryItem] = [:]
        var duplicateIDs = Set<UUID>()
        var canonicalSelectedIDs = Set<UUID>()
        for url in urls where supportedPackageExtensions.contains(url.pathExtension.lowercased()) {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let decoded: DecodedPatchPackage?
                if let contentKey = try PatchKeyStore.load(for: summary) {
                    decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
                } else if summary.isPasswordProtected {
                    decoded = nil
                } else {
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                var item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url
                )
                if let project = item.project,
                   let trusted = trustedPayloadFingerprint(for: summary.packageID),
                   trusted != projectPayloadFingerprint(project) {
                    log("patch: refusing package with modified payload \(url.lastPathComponent); restore-only until the feed repairs it")
                    item.project = nil
                    item.contentKey = nil
                }
                if let canonicalFilename = canonicalBundledPackageFilenames[summary.packageID],
                   canonicalFilename.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame,
                   item.project != nil {
                    if let previous = byID[summary.packageID],
                       previous.packageURL != item.packageURL {
                        log("patch: selected bundled package \(canonicalFilename) over legacy duplicate \(previous.packageURL.lastPathComponent)")
                    }
                    byID[summary.packageID] = item
                    duplicateIDs.remove(summary.packageID)
                    canonicalSelectedIDs.insert(summary.packageID)
                    continue
                }
                if canonicalSelectedIDs.contains(summary.packageID) {
                    log("patch: ignored legacy duplicate package ID \(summary.packageID.uuidString) in \(url.lastPathComponent)")
                    continue
                }
                if duplicateIDs.contains(summary.packageID) {
                    log("patch: skipped duplicate package ID \(summary.packageID.uuidString) in \(url.lastPathComponent)")
                    continue
                }
                if let previous = byID.removeValue(forKey: summary.packageID) {
                    duplicateIDs.insert(summary.packageID)
                    let restoreCandidate = [previous, item].first { candidate in
                        let name = candidate.project?.name
                            ?? candidate.packageURL.deletingPathExtension().lastPathComponent
                        return bundledProjectNames.contains {
                            projectNameMatches(expected: $0, actual: name)
                        }
                    } ?? previous
                    var restoreOnlyItem = restoreCandidate
                    restoreOnlyItem.project = nil
                    restoreOnlyItem.contentKey = nil
                    byID[summary.packageID] = restoreOnlyItem
                    log("patch: refusing activation for duplicate package ID \(summary.packageID.uuidString) in \(previous.packageURL.lastPathComponent) and \(url.lastPathComponent); keeping restore-only entry")
                    continue
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent)")
            }
        }
        for item in byID.values where item.summary.schemaVersion >= 2 {
            guard let project = item.project, !isBundledProject(project) else { continue }
            do {
                _ = try PatchWorkspaceService.ensureWorkspace(for: project)
            } catch {
                log("patch: workspace unavailable for \(project.id.uuidString)")
            }
        }
        return byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
    }

    static func readPackage(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("TRYSTORE")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("TRYSTORE")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func installDeliveredPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        createWorkspace: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        // `existingURL` can also be the canonical destination for a first
        // remote install. Only read it when a prior package actually exists.
        let previousData: Data?
        if let existingURL, fileManager.fileExists(atPath: existingURL.path) {
            previousData = try readPackage(at: existingURL)
        } else {
            previousData = nil
        }
        var savedURL: URL?
        do {
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2, createWorkspace {
                _ = try PatchWorkspaceService.replaceWorkspace(
                    with: decoded.project,
                    fileManager: fileManager
                )
            } else if summary.schemaVersion >= 2 {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: [.atomic, .completeFileProtection]
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
    }

    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              let baseProject = item.project,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        guard !isBundledProject(baseProject) else { return baseProject }
        let workspace = try PatchWorkspaceService.ensureWorkspace(for: baseProject, fileManager: fileManager)
        let project = try PatchWorkspaceService.snapshot(
            baseProject: baseProject,
            workspaceURL: workspace,
            fileManager: fileManager
        )
        let original = try readPackage(at: item.packageURL)
        let updated = try PatchPackageCodec.update(
            original,
            project: project,
            contentKey: contentKey,
            schemaVersion: PatchPackageCodec.latestSchemaVersion
        )
        _ = try save(
            data: updated,
            projectName: project.name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return project
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch" : String(result)
    }

    // MARK: - Payload trust

    private static func trustedPayloadKey(_ packageID: UUID) -> String {
        "patch.trustedPayload.\(packageID.uuidString.lowercased())"
    }

    private static func trustedPayloadFingerprint(for packageID: UUID) -> Data? {
        if let stored = UserDefaults.standard.string(forKey: trustedPayloadKey(packageID)),
           let data = data(fromHex: stored) {
            return data
        }
        guard let seeded = bundledPayloadFingerprints[packageID] else { return nil }
        return data(fromHex: seeded)
    }

    /// Canonical identity of everything that changes the game file. Name, id,
    /// targets and replacement bytes are all covered, so an aim package that
    /// was swapped with an Antena payload cannot pass as the aim package.
    private static func projectPayloadFingerprint(_ project: PatchProject) -> Data {
        var hasher = SHA256()
        func feed(_ value: String) {
            hasher.update(data: Data(value.utf8))
            hasher.update(data: Data([0]))
        }
        feed("v1")
        feed(project.id.uuidString)
        feed(project.name)
        for bundleID in project.bundleIdentifiers.sorted() {
            feed("b")
            feed(bundleID)
        }
        for directory in project.directories.sorted(by: {
            $0.bundleID + "\0" + $0.relativePath < $1.bundleID + "\0" + $1.relativePath
        }) {
            feed("d")
            feed(directory.bundleID)
            feed(directory.relativePath)
        }
        for rule in project.rules.sorted(by: {
            $0.bundleID + "\0" + $0.relativePath < $1.bundleID + "\0" + $1.relativePath
        }) {
            feed("r")
            feed(rule.bundleID)
            feed(rule.relativePath)
            feed(rule.replacementFilename)
            hasher.update(data: Data(SHA256.hash(data: rule.replacementData)))
        }
        return Data(hasher.finalize())
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func data(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func removeDuplicatePackages(
        packageID: UUID,
        keeping destination: URL,
        in root: URL,
        fileManager: FileManager
    ) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }
        let canonicalDestination = destination.standardizedFileURL
        for url in urls where supportedPackageExtensions.contains(url.pathExtension.lowercased()) {
            guard url.standardizedFileURL != canonicalDestination,
                  let data = try? readPackage(at: url),
                  let summary = try? PatchPackageCodec.inspect(data),
                  summary.packageID == packageID else { continue }
            try? fileManager.removeItem(at: url)
            log("patch: removed stale duplicate package \(url.lastPathComponent)")
        }
    }
}
