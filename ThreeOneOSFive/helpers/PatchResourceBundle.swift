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
        ("HEAD.3105", "r_91c3f2"),
        ("NECK.3105", "r_5d7a10"),
        ("HSPESSCOSO.3105", "r_8e4f1b"),
        ("HS SLA PECHO.3105", "r_6b0c5d"),
        ("SilentAim.3105", "r_2d9a74"),
        ("HOLOGRAMAARMAS.3105", "r_5f1c38"),
        ("HOLOGRAMAPERSONAJE.3105", "r_4b8e26"),
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
