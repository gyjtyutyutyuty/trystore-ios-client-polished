import CryptoKit
import Foundation
import UIKit

enum PatchResourceBundle {
    enum BundleError: Error {
        case invalidKey
        case missingAsset(String)
        case invalidCiphertext
    }

    private static let assets: [(resourceName: String, assetName: String)] = [
        ("HEAD.3105", "HEAD"),
        ("NECK.3105", "NECK"),
        ("HSPESSCOSO.3105", "HS_PESSCOSO"),
        ("HS SLA PECHO.3105", "HS_SLA_PECHO"),
        ("HOLOGRAMAARMAS.3105", "HOLOGRAMA_ARMAS"),
        ("HOLOGRAMAPERSONAJE.3105", "HOLOGRAMA_PERSONAJE"),
        ("HOLOGRAMAEXCLUSIVO(2).3105", "HOLOGRAMA_EXCLUSIVO_VERDE"),
        ("HOLOGRAMAEXCLUSIVO(3).3105", "HOLOGRAMA_EXCUSIVO_ROSADO"),
    ]

    static func load(using keyData: Data) throws -> [String: Data] {
        guard keyData.count == 32 else { throw BundleError.invalidKey }
        let key = SymmetricKey(data: keyData)
        var resources: [String: Data] = [:]
        resources.reserveCapacity(assets.count)

        for entry in assets {
            guard let encrypted = NSDataAsset(name: entry.assetName)?.data else {
                throw BundleError.missingAsset(entry.assetName)
            }
            guard let sealedBox = try? AES.GCM.SealedBox(combined: encrypted) else {
                throw BundleError.invalidCiphertext
            }
            do {
                resources[entry.resourceName] = try AES.GCM.open(sealedBox, using: key)
            } catch {
                throw BundleError.invalidCiphertext
            }
        }
        return resources
    }
}
