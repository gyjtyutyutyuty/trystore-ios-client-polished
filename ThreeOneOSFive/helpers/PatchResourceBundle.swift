import CryptoKit
import Foundation
import UIKit

enum PatchResourceBundle {
    enum BundleError: Error {
        case invalidKey
    }

    private static let assets: [(resourceName: String, assetName: String)] = [
        ("HEAD.3105", "HEAD"),
        ("NECK.3105", "NECK"),
        ("HSPESSCOSO.3105", "HS_PESSCOSO"),
        ("HS SLA PECHO.3105", "HS_SLA_PECHO"),
        ("HOLOGRAMAARMAS.3105", "HOLOGRAMA_ARMAS"),
        ("HOLOGRAMAPERSONAJE.3105", "HOLOGRAMA_PERSONAJE"),
        ("HOLOGRAMAEXCLUSIVO(4).3105", "HOLOGRAMA_EXCLUSIVO_VERDE")
    ]

    static func load(using keyData: Data) throws -> [String: Data] {
        guard keyData.count == 32 else { throw BundleError.invalidKey }
        let key = SymmetricKey(data: keyData)
        var resources: [String: Data] = [:]
        resources.reserveCapacity(assets.count)

        for entry in assets {
            guard let encrypted = NSDataAsset(name: entry.assetName, bundle: .main)?.data else {
                log("patch: encrypted asset missing from catalog: \(entry.assetName)")
                continue
            }
            guard let sealedBox = try? AES.GCM.SealedBox(combined: encrypted) else {
                log("patch: encrypted asset has invalid format: \(entry.assetName)")
                continue
            }
            do {
                resources[entry.resourceName] = try AES.GCM.open(sealedBox, using: key)
            } catch {
                log("patch: encrypted asset authentication failed: \(entry.assetName)")
            }
        }
        return resources
    }
}
