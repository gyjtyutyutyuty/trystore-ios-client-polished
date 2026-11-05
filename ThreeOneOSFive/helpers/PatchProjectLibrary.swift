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
            try installImportedPackage(
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

    static func installBundledPackageDataIfNeeded(
        _ sourceData: Data,
        projectName: String,
        password: String? = nil,
        fileManager: FileManager = .default
    ) {
        guard let source = try? PatchPackageCodec.decodeBundledResource(sourceData) else {
            log("patch: bundled package decode failed: \(projectName)")
            return
        }
        guard projectNameMatches(expected: projectName, actual: source.decoded.project.name) else {
            log("patch: bundled package identity mismatch: expected \(projectName), payload \(source.decoded.project.name)")
            return
        }
        guard let root = try? packageRootURL(fileManager: fileManager) else {
            log("patch: bundled package storage unavailable: \(projectName)")
            return
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
                    return
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
            try installImportedPackage(
                data: normalizedData.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: normalizedData.contentKey),
                summary: normalizedSummary,
                existingURL: nil,
                createWorkspace: false,
                fileManager: fileManager
            )
            UserDefaults.standard.set(sourceRevision, forKey: revisionKey)
            log("patch: installed IPA-bundled snapshot: \(projectName)")
        } catch {
            log("patch: bundled file install failed: \(projectName) — \(error)")
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
                let item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url
                )
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

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        createWorkspace: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        let previousData = try existingURL.map { try readPackage(at: $0) }
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
}
