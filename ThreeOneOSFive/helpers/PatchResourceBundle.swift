import Foundation

enum PatchResourceBundle {
    static let packageFiles = [
        "EXCLUSIVO AZUL.TRYSTORE",
        "HEAD.TRYSTORE",
        "HS SLA PECHO.TRYSTORE",
        "HSPESSCOSO.TRYSTORE",
        "NECK.TRYSTORE",
        "TryStore.TRYSTORE",
        "HOLOGRAMAEXCLUSIVO(4).TRYSTORE",
        "HOLOGRAMAEXCLUSIVO(5).TRYSTORE",
        "Cuello y Drag.TRYSTORE",
        "Pecho3105.TRYSTORE",
        "CUELLO3105.TRYSTORE"
    ]

    static func load() -> [(fileName: String, data: Data)] {
        packageFiles.compactMap { fileName in
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("Patches", isDirectory: true)
                .appendingPathComponent(fileName)
            guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                log("patch: bundled package missing: \(fileName)")
                return nil
            }
            return (fileName, data)
        }
    }
}
