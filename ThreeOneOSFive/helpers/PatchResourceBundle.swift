import CryptoKit
import Foundation
import UIKit

enum PatchResourceBundle {
    enum BundleError: Error {
        case invalidKey
    }

    private static let assets: [(resourceName: String, assetName: String)] = [
        ("HEAD.TRYSTORE", "HEAD"),
        ("NECK.TRYSTORE", "NECK"),
        ("HSPESSCOSO.TRYSTORE", "HS_PESSCOSO"),
        ("HS SLA PECHO.TRYSTORE", "HS_SLA_PECHO"),
        ("BALAS.TRYSTORE", "BALAS"),
        ("ARMAS.TRYSTORE", "ARMAS"),
        ("HOLOGRAMAEXCLUSIVO(4).TRYSTORE", "HOLOGRAMA_EXCLUSIVO_VERDE"),
        ("HOLOGRAMAEXCLUSIVO(5).TRYSTORE", "HOLOGRAMA_EXCLUSIVO_ROSADO")
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
