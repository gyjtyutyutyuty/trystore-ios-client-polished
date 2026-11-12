import Foundation
import AirliftFFI

/// The Airlift pairing-tunnel path, for builds with no local sandbox backend
/// (iOS 18.7.2 and later) or where worse_query cannot run because the signing
/// profile carries no App Group.
///
/// Patches were applied over this tunnel before the local-only rewrite; the
/// transaction layer still takes a remote writer/reader, so this is the only
/// piece that had to come back.
enum PairingTunnelService {
    private static let maximumRemotePathBytes = 768

    private static let logCallback: ALLogCallback = { _, message in
        guard let message else { return }
        let line = String(cString: message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        log("Airlift: \(line)")
    }

    static func remoteContainerPath(pairingFileURL: URL, bundleID: String) throws -> String {
        var containerPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let returnCode = pairingFileURL.path.withCString { pairingPath in
            bundleID.withCString { identifier in
                al_find_app_container(
                    pairingPath,
                    identifier,
                    logCallback,
                    nil,
                    &containerPointer,
                    &errorPointer
                )
            }
        }
        defer {
            if let containerPointer { al_string_free(containerPointer) }
            if let errorPointer { al_string_free(errorPointer) }
        }
        guard returnCode == 0,
              let containerPointer,
              let path = String(validatingUTF8: containerPointer),
              path.hasPrefix("/var/mobile/Containers/Data/Application/") else {
            throw PatchPackageError.targetAppUnavailable(bundleID)
        }
        return path
    }

    static func writeFile(
        bundleID: String,
        relativePath rawRelativePath: String,
        data: Data,
        pairingFileURL: URL,
        remoteContainerPath: String
    ) throws {
        let relativePath: String
        do {
            relativePath = try PatchPathValidator.canonicalRelativePath(rawRelativePath)
        } catch {
            throw PatchPackageError.unsafeTargetPath
        }
        let leafName = (relativePath as NSString).lastPathComponent
        guard remoteContainerPath.hasPrefix("/var/mobile/Containers/Data/Application/"),
              !leafName.hasPrefix(".") else {
            throw PatchPackageError.unsafeTargetPath
        }

        let remoteTarget = URL(fileURLWithPath: remoteContainerPath, isDirectory: true)
            .appendingPathComponent(relativePath)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("3105-patch-remote-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sourceDirectory) }
            try data.write(
                to: sourceDirectory.appendingPathComponent(remoteTarget.lastPathComponent),
                options: .atomic
            )

            var errorPointer: UnsafeMutablePointer<CChar>?
            let returnCode = pairingFileURL.path.withCString { pairingPath in
                sourceDirectory.path.withCString { sourcePath in
                    remoteTarget.deletingLastPathComponent().path.withCString { targetDirectory in
                        al_exploit_write_dir(
                            pairingPath,
                            sourcePath,
                            targetDirectory,
                            logCallback,
                            nil,
                            &errorPointer
                        )
                    }
                }
            }
            defer {
                if let errorPointer { al_string_free(errorPointer) }
            }
            guard returnCode == 0 else {
                let detail = errorPointer.map { String(cString: $0) }
                    ?? "Remote file write failed (\(returnCode))."
                throw PatchPackageError.remoteReplacementFailed(detail)
            }
            log("patch: Airlift wrote \(bundleID)/\(relativePath) bytes=\(data.count)")
        } catch let error as PatchPackageError {
            throw error
        } catch {
            throw PatchPackageError.remoteReplacementFailed(error.localizedDescription)
        }
    }

    static func readFile(
        bundleID: String,
        relativePath rawRelativePath: String,
        pairingFileURL: URL,
        remoteContainerPath: String
    ) throws -> Data {
        let relativePath: String
        do {
            relativePath = try PatchPathValidator.canonicalRelativePath(rawRelativePath)
        } catch {
            throw PatchPackageError.unsafeTargetPath
        }
        guard remoteContainerPath.hasPrefix("/var/mobile/Containers/Data/Application/"),
              (remoteContainerPath + "/" + relativePath).utf8.count <= maximumRemotePathBytes else {
            throw PatchPackageError.unsafeTargetPath
        }

        let remoteTarget = URL(fileURLWithPath: remoteContainerPath, isDirectory: true)
            .appendingPathComponent(relativePath)
        _ = try validatedRemoteTarget(remoteTarget.path)
        log("patch: Airlift remote read started \(bundleID)/\(relativePath)")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("3105-remote-read-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let returnCode = pairingFileURL.path.withCString { pairingPath in
            remoteTarget.path.withCString { targetPath in
                outputURL.path.withCString { outputPath in
                    al_exploit_read_file(
                        pairingPath,
                        targetPath,
                        outputPath,
                        logCallback,
                        nil,
                        &errorPointer
                    )
                }
            }
        }
        let remoteError = errorPointer.map { String(cString: $0) }
        if let errorPointer { al_string_free(errorPointer) }
        guard returnCode == 0 else {
            let detail = remoteError ?? "Remote file read failed (\(returnCode))."
            log("patch: Airlift remote read failed \(bundleID)/\(relativePath) rc=\(returnCode) detail=\(detail)")
            if detail.contains("stat recovered target: Afc(ObjectNotFound)") {
                throw PatchPackageError.remoteTargetMissing
            }
            throw PatchPackageError.remoteReplacementFailed(detail)
        }
        let data: Data
        do {
            data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        } catch {
            throw PatchPackageError.remoteReplacementFailed("Remote file backup could not be loaded.")
        }
        guard data.count <= 32 * 1_024 * 1_024 else {
            throw PatchPackageError.sizeLimitExceeded
        }
        log("patch: Airlift read \(bundleID)/\(relativePath) bytes=\(data.count)")
        return data
    }

    /// The tunnel only ever touches `/var/mobile` containers, and only through
    /// a path built from a validated relative component.
    private static func validatedRemoteTarget(_ rawPath: String) throws -> URL {
        guard rawPath.utf8.count <= maximumRemotePathBytes,
              !rawPath.contains("\\"),
              !rawPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw PatchPackageError.unsafeTargetPath
        }

        let path: String
        if rawPath.hasPrefix("/private/var/mobile/") {
            path = String(rawPath.dropFirst("/private".count))
        } else if rawPath.hasPrefix("/var/mobile/") {
            path = rawPath
        } else {
            throw PatchPackageError.unsafeTargetPath
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "",
              components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.count > 3 else {
            throw PatchPackageError.unsafeTargetPath
        }
        return URL(fileURLWithPath: path, isDirectory: false)
    }
}
