import Foundation

enum PatchResourceBundle {
    private static let resourceNames = [
        "HEAD.TRYSTORE",
        "NECK.TRYSTORE",
        "HSPESSCOSO.TRYSTORE",
        "HS SLA PECHO.TRYSTORE",
        "EXCLUSIVO AZUL.TRYSTORE",
        "TryStore.TRYSTORE",
        "HOLOGRAMAEXCLUSIVO(4).TRYSTORE",
        "HOLOGRAMAEXCLUSIVO(5).TRYSTORE",
        "Cuello y Drag.TRYSTORE",
        "Pecho3105.TRYSTORE",
        "CUELLO3105.TRYSTORE"
    ]

    static func load() -> [String: Data] {
        guard let patchDirectory = Bundle.main.resourceURL?.appendingPathComponent("Patches", isDirectory: true) else {
            log("patch: bundled Patches directory is unavailable")
            return [:]
        }

        var resources: [String: Data] = [:]
        resources.reserveCapacity(resourceNames.count)
        for name in resourceNames {
            let url = patchDirectory.appendingPathComponent(name, isDirectory: false)
            do {
                resources[name] = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                log("patch: local bundled package could not be read: \(name) (\(error.localizedDescription))")
            }
        }
        return resources
    }
}
