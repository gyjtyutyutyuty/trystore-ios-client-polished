import Foundation
import SceneKit
import UIKit
import WebKit

// MARK: - Cache

/// Downloaded garment meshes live in Caches, keyed by the catalogue slug.
enum GarmentStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Garments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func cacheURL(slug: String) -> URL {
        let safe = slug.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent(safe).appendingPathExtension("glb")
    }

    static func cachedURL(for item: PlayerOutfitItem) -> URL? {
        guard let slug = item.pageURL?.lastPathComponent, !slug.isEmpty else { return nil }
        let url = cacheURL(slug: slug)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func isCached(_ item: PlayerOutfitItem) -> Bool {
        cachedURL(for: item) != nil
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Model

/// A garment parsed from the catalogue. `height`, `width` and `depth` are in
/// the loader's normalised space, where the longest side is 1. `node` is the
/// detached, centred scene node, ready to attach to the character.
struct GarmentModel {
    let node: SCNNode
    let height: CGFloat
    let width: CGFloat
    let depth: CGFloat
}

/// A downloaded garment that belongs on the character.
struct PlayerGarment: Identifiable, Equatable {
    let id: String
    let slot: PlayerOutfitSlot
    let url: URL
}

/// Where a slot sits on the character. The body is one unit tall and centred
/// on the origin, so these values are direct scene coordinates.
struct GarmentFit {
    let centerY: CGFloat
    let span: CGFloat
    let z: CGFloat
}

extension PlayerOutfitSlot {
    /// The catalogue exports each item as a standalone scan with its own
    /// origin, so the only reliable placement is a per-slot box: centre the
    /// mesh on the body region and scale its longest side to the slot span.
    var garmentFit: GarmentFit? {
        switch self {
        case .hair: return GarmentFit(centerY: 0.44, span: 0.20, z: 0.00)
        case .face: return GarmentFit(centerY: 0.40, span: 0.13, z: 0.05)
        case .mask: return GarmentFit(centerY: 0.355, span: 0.17, z: 0.06)
        case .top: return GarmentFit(centerY: 0.09, span: 0.36, z: 0.02)
        case .pants: return GarmentFit(centerY: -0.17, span: 0.34, z: 0.02)
        case .shoes: return GarmentFit(centerY: -0.43, span: 0.16, z: 0.03)
        case .pin, .title, .other: return nil
        }
    }
}

// MARK: - Download

/// The catalogue serves each garment as a GLB behind a single-use ticket bound
/// to the browser session. A hidden `WKWebView` opens the item page, starts the
/// viewer, then fetches the ticket URL in-page and hands the bytes back as
/// base64. Each call owns its web view, so downloads can run concurrently.
@MainActor
final class GarmentDownloader {
    static let shared = GarmentDownloader()

    /// Two hidden pages at a time. Ten players with three 3D items each would
    /// otherwise open thirty web views on the main thread at once.
    private let gate = AsyncGate(value: 2)

    func download(item: PlayerOutfitItem, timeout: TimeInterval = 50) async throws -> URL {
        guard let pageURL = item.pageURL else { throw PlayerIntelError.outfitUnavailable }

        if let cached = GarmentStore.cachedURL(for: item) {
            return cached
        }

        await gate.wait()
        defer { Task { await self.gate.signal() } }

        let destination = GarmentStore.cacheURL(slug: pageURL.lastPathComponent)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.captureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.alpha = 0.02

        attach(view)
        defer { detach(view) }

        _ = view.load(URLRequest(url: pageURL))

        let deadline = Date().addingTimeInterval(timeout)
        var startedViewer = false

        while Date() < deadline, !Task.isCancelled {
            try await Task.sleep(nanoseconds: 700_000_000)

            if !startedViewer {
                let started = try? await view.evaluateJavaScript(Self.startViewerScript)
                startedViewer = (started as? Bool) ?? false
            }

            guard let payload = try? await view.evaluateJavaScript(Self.fetchModelScript),
                  let text = payload as? String,
                  let data = text.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard let base64 = root["base64"] as? String,
                  let model = Data(base64Encoded: base64),
                  model.count > 20,
                  model.prefix(4) == Data("glTF".utf8)
            else { continue }

            try model.write(to: destination, options: .atomic)
            return destination
        }

        throw PlayerIntelError.outfitUnavailable
    }

    private func attach(_ view: WKWebView) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else {
            return
        }
        window.addSubview(view)
    }

    private func detach(_ view: WKWebView) {
        view.stopLoading()
        view.removeFromSuperview()
    }

    private static let startViewerScript = """
    (function () {
      var button = document.querySelector('[data-ffwiki-model-open]');
      if (!button) { return false; }
      button.disabled = false;
      button.click();
      return true;
    })()
    """

    private static let fetchModelScript = """
    (function () {
      if (window.__tsGarmentBase64) {
        return JSON.stringify({ state: 'ready', base64: window.__tsGarmentBase64 });
      }
      return JSON.stringify({ state: 'waiting' });
    })()
    """

    /// Runs before the page's own scripts. The model viewer fetches a
    /// single-use ticket URL, so re-fetching it from here can 404 once the
    /// viewer consumed it. Cloning the response as it arrives is the only
    /// reliable way to get the bytes.
    private static let captureScript = """
    (function () {
      if (window.__tsGarmentHook) { return; }
      window.__tsGarmentHook = true;
      window.__tsGarmentBase64 = '';

      function isModel(url) {
        return String(url || '').indexOf('/api/ffwiki/model/?ticket=') >= 0;
      }

      function store(buffer) {
        var bytes = new Uint8Array(buffer);
        var binary = '';
        var chunk = 0x8000;
        for (var i = 0; i < bytes.length; i += chunk) {
          binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        window.__tsGarmentBase64 = btoa(binary);
      }

      var originalFetch = window.fetch;
      window.fetch = function (input, init) {
        var url = typeof input === 'string' ? input : (input && input.url);
        var promise = originalFetch.apply(this, arguments);
        if (isModel(url)) {
          promise.then(function (response) {
            if (!response.ok) { return; }
            response.clone().arrayBuffer().then(store).catch(function () {});
          }).catch(function () {});
        }
        return promise;
      };

      var originalOpen = XMLHttpRequest.prototype.open;
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__tsGarmentURL = url;
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var request = this;
        if (isModel(request.__tsGarmentURL)) {
          request.addEventListener('load', function () {
            if (request.status < 200 || request.status >= 300) { return; }
            var response = request.response;
            if (response instanceof ArrayBuffer) {
              store(response);
            } else if (response instanceof Blob) {
              response.arrayBuffer().then(store).catch(function () {});
            }
          });
        }
        return originalSend.apply(this, arguments);
      };
    })()
    """
}

/// Small counting gate so ten players do not open ten web views at once.
actor AsyncGate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        available = max(1, value)
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }
}

// MARK: - GLB

enum GLBError: Error {
    case badMagic
    case corrupt
    case missingJSON
    case missingBIN
    case unsupported(String)
}

/// Minimal glTF 2.0 binary reader. It covers what the catalogue emits: float
/// positions, normals and UVs, 16/32-bit indices, one base-colour texture, and
/// node transforms. Skins and animations are ignored.
enum GLBSceneLoader {
    static func model(from url: URL) throws -> GarmentModel {
        let data = try Data(contentsOf: url)
        guard data.count > 20, data.prefix(4) == Data("glTF".utf8) else {
            throw GLBError.badMagic
        }
        guard readUInt32(data, 4) == 2 else {
            throw GLBError.unsupported("glTF version")
        }

        var jsonData: Data?
        var binary: Data?
        var offset = 12

        while offset + 8 <= data.count {
            let length = Int(readUInt32(data, offset))
            let type = readUInt32(data, offset + 4)
            offset += 8
            guard length >= 0, offset + length <= data.count else { throw GLBError.corrupt }
            let chunk = data.subdata(in: offset..<(offset + length))
            if type == 0x4E4F534A { jsonData = chunk }
            if type == 0x004E4942 { binary = chunk }
            offset += length
        }

        guard let jsonData else { throw GLBError.missingJSON }
        guard let binary else { throw GLBError.missingBIN }

        let gltf = try JSONDecoder().decode(GLTF.self, from: jsonData)
        let root = SCNNode()

        if let sceneIndex = gltf.scene,
           let scenes = gltf.scenes,
           sceneIndex < scenes.count,
           let nodes = scenes[sceneIndex].nodes {
            for index in nodes {
                root.addChildNode(try makeNode(index, gltf: gltf, binary: binary))
            }
        } else if let nodes = gltf.nodes {
            for index in nodes.indices {
                root.addChildNode(try makeNode(index, gltf: gltf, binary: binary))
            }
        }

        guard let bounds = bounds(of: root) else {
            throw GLBError.unsupported("empty mesh")
        }

        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )
        let longest = max(size.x, max(size.y, size.z))
        guard longest > 0 else { throw GLBError.unsupported("flat mesh") }

        root.position = SCNVector3(-center.x, -center.y, -center.z)

        let container = SCNNode()
        container.name = "garment-container"
        container.addChildNode(root)
        container.scale = SCNVector3(1 / longest, 1 / longest, 1 / longest)

        return GarmentModel(
            node: container,
            height: CGFloat(size.y / longest),
            width: CGFloat(size.x / longest),
            depth: CGFloat(size.z / longest)
        )
    }

    // MARK: Nodes

    private static func makeNode(_ index: Int, gltf: GLTF, binary: Data) throws -> SCNNode {
        guard let nodes = gltf.nodes, index < nodes.count else {
            throw GLBError.corrupt
        }
        let definition = nodes[index]
        let node = SCNNode()
        node.name = definition.name

        if let meshIndex = definition.mesh,
           let meshes = gltf.meshes,
           meshIndex < meshes.count {
            for primitive in meshes[meshIndex].primitives {
                let child = SCNNode(geometry: try geometry(for: primitive, gltf: gltf, binary: binary))
                node.addChildNode(child)
            }
        }

        if let matrix = definition.matrix, matrix.count == 16 {
            node.transform = SCNMatrix4(
                m11: matrix[0], m12: matrix[4], m13: matrix[8], m14: matrix[12],
                m21: matrix[1], m22: matrix[5], m23: matrix[9], m24: matrix[13],
                m31: matrix[2], m32: matrix[6], m33: matrix[10], m34: matrix[14],
                m41: matrix[3], m42: matrix[7], m43: matrix[11], m44: matrix[15]
            )
        } else {
            if let translation = definition.translation, translation.count == 3 {
                node.position = SCNVector3(translation[0], translation[1], translation[2])
            }
            if let rotation = definition.rotation, rotation.count == 4 {
                node.orientation = SCNQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])
            }
            if let scale = definition.scale, scale.count == 3 {
                node.scale = SCNVector3(scale[0], scale[1], scale[2])
            }
        }

        if let children = definition.children {
            for child in children {
                node.addChildNode(try makeNode(child, gltf: gltf, binary: binary))
            }
        }

        return node
    }

    // MARK: Geometry

    private static func geometry(for primitive: GLTF.Primitive, gltf: GLTF, binary: Data) throws -> SCNGeometry {
        guard let positionIndex = primitive.attributes["POSITION"],
              let accessors = gltf.accessors,
              positionIndex < accessors.count else {
            throw GLBError.corrupt
        }

        let position = accessors[positionIndex]
        guard position.componentType == 5126, position.type == "VEC3" else {
            throw GLBError.unsupported("POSITION format")
        }

        let positionData = try data(for: positionIndex, gltf: gltf, binary: binary)
        var sources = [
            SCNGeometrySource(
                data: positionData,
                semantic: .vertex,
                vectorCount: position.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: 4,
                dataOffset: 0,
                dataStride: 12
            )
        ]

        if let normalIndex = primitive.attributes["NORMAL"],
           normalIndex < accessors.count,
           accessors[normalIndex].componentType == 5126,
           accessors[normalIndex].type == "VEC3" {
            let normalData = try data(for: normalIndex, gltf: gltf, binary: binary)
            sources.append(
                SCNGeometrySource(
                    data: normalData,
                    semantic: .normal,
                    vectorCount: accessors[normalIndex].count,
                    usesFloatComponents: true,
                    componentsPerVector: 3,
                    bytesPerComponent: 4,
                    dataOffset: 0,
                    dataStride: 12
                )
            )
        }

        if let uvIndex = primitive.attributes["TEXCOORD_0"],
           uvIndex < accessors.count,
           accessors[uvIndex].componentType == 5126,
           accessors[uvIndex].type == "VEC2" {
            let uvData = try data(for: uvIndex, gltf: gltf, binary: binary)
            sources.append(
                SCNGeometrySource(
                    data: uvData,
                    semantic: .texcoord,
                    vectorCount: accessors[uvIndex].count,
                    usesFloatComponents: true,
                    componentsPerVector: 2,
                    bytesPerComponent: 4,
                    dataOffset: 0,
                    dataStride: 8
                )
            )
        }

        let element: SCNGeometryElement
        if let index = primitive.indices, index < accessors.count {
            let accessor = accessors[index]
            let bytesPerIndex = componentSize(accessor.componentType)
            guard bytesPerIndex == 2 || bytesPerIndex == 4 else {
                throw GLBError.unsupported("index format")
            }
            let indexData = try data(for: index, gltf: gltf, binary: binary)
            element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: accessor.count / 3,
                bytesPerIndex: bytesPerIndex
            )
        } else {
            let indices = (0..<position.count).map { UInt32($0) }
            element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        }

        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material(index: primitive.material, gltf: gltf, binary: binary)]
        return geometry
    }

    private static func material(index: Int?, gltf: GLTF, binary: Data) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.isDoubleSided = true
        material.diffuse.contents = UIColor(white: 0.82, alpha: 1)

        guard let index,
              let materials = gltf.materials,
              index < materials.count,
              let definition = materials[index] else {
            return material
        }

        material.isDoubleSided = definition.doubleSided ?? true

        if let pbr = definition.pbrMetallicRoughness {
            if let reference = pbr.baseColorTexture,
               let textures = gltf.textures,
               reference.index < textures.count,
               let source = textures[reference.index].source,
               let images = gltf.images,
               source < images.count,
               let image = image(images[source], gltf: gltf, binary: binary) {
                material.diffuse.contents = image
            }
            if let factor = pbr.baseColorFactor, factor.count >= 4 {
                material.diffuse.contents = UIColor(
                    red: CGFloat(factor[0]),
                    green: CGFloat(factor[1]),
                    blue: CGFloat(factor[2]),
                    alpha: CGFloat(factor[3])
                )
            }
        }

        return material
    }

    private static func image(_ definition: GLTF.ImageDef, gltf: GLTF, binary: Data) -> UIImage? {
        guard let viewIndex = definition.bufferView,
              let views = gltf.bufferViews,
              viewIndex < views.count else {
            return nil
        }
        let view = views[viewIndex]
        let start = view.byteOffset ?? 0
        guard start + view.byteLength <= binary.count else { return nil }
        return UIImage(data: binary.subdata(in: start..<(start + view.byteLength)))
    }

    // MARK: Accessors

    private static func data(for accessorIndex: Int, gltf: GLTF, binary: Data) throws -> Data {
        guard let accessors = gltf.accessors,
              accessorIndex < accessors.count else {
            throw GLBError.corrupt
        }
        let accessor = accessors[accessorIndex]
        guard let viewIndex = accessor.bufferView,
              let views = gltf.bufferViews,
              viewIndex < views.count else {
            throw GLBError.unsupported("sparse accessor")
        }
        let view = views[viewIndex]
        let components = componentCount(accessor.type)
        let size = componentSize(accessor.componentType)
        let tight = components * size
        let stride = view.byteStride ?? tight
        let start = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0)
        let length = accessor.count * stride

        guard components > 0, size > 0, start >= 0, length >= 0, start + length <= binary.count else {
            throw GLBError.corrupt
        }

        if stride == tight {
            return binary.subdata(in: start..<(start + accessor.count * tight))
        }

        var packed = Data(capacity: accessor.count * tight)
        for index in 0..<accessor.count {
            let element = start + index * stride
            packed.append(binary.subdata(in: element..<(element + tight)))
        }
        return packed
    }

    private static func bounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minimum = SCNVector3(
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude
        )
        var maximum = SCNVector3(
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude
        )
        var found = false

        root.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            var low = SCNVector3Zero
            var high = SCNVector3Zero
            guard child.getBoundingBoxMin(&low, max: &high) else { return }

            for corner in corners(low, high) {
                let point = child.convertPosition(corner, to: root)
                minimum = SCNVector3(
                    Swift.min(minimum.x, point.x),
                    Swift.min(minimum.y, point.y),
                    Swift.min(minimum.z, point.z)
                )
                maximum = SCNVector3(
                    Swift.max(maximum.x, point.x),
                    Swift.max(maximum.y, point.y),
                    Swift.max(maximum.z, point.z)
                )
                found = true
            }
        }

        return found ? (minimum, maximum) : nil
    }

    private static func corners(_ low: SCNVector3, _ high: SCNVector3) -> [SCNVector3] {
        [
            SCNVector3(low.x, low.y, low.z),
            SCNVector3(low.x, low.y, high.z),
            SCNVector3(low.x, high.y, low.z),
            SCNVector3(low.x, high.y, high.z),
            SCNVector3(high.x, low.y, low.z),
            SCNVector3(high.x, low.y, high.z),
            SCNVector3(high.x, high.y, low.z),
            SCNVector3(high.x, high.y, high.z)
        ]
    }

    // MARK: Bytes

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private static func componentSize(_ type: Int) -> Int {
        switch type {
        case 5120, 5121: return 1
        case 5122, 5123: return 2
        case 5125, 5126: return 4
        default: return 0
        }
    }

    private static func componentCount(_ type: String) -> Int {
        switch type {
        case "SCALAR": return 1
        case "VEC2": return 2
        case "VEC3": return 3
        case "VEC4": return 4
        case "MAT4": return 16
        default: return 0
        }
    }

    // MARK: Schema

    private struct GLTF: Decodable {
        struct Asset: Decodable { let version: String }
        struct SceneDef: Decodable { let nodes: [Int]? }
        struct NodeDef: Decodable {
            let name: String?
            let mesh: Int?
            let children: [Int]?
            let matrix: [Float]?
            let translation: [Float]?
            let rotation: [Float]?
            let scale: [Float]?
        }
        struct MeshDef: Decodable {
            let name: String?
            let primitives: [Primitive]
        }
        struct Primitive: Decodable {
            let attributes: [String: Int]
            let indices: Int?
            let material: Int?
        }
        struct Accessor: Decodable {
            let bufferView: Int?
            let byteOffset: Int?
            let componentType: Int
            let count: Int
            let type: String
            let min: [Float]?
            let max: [Float]?
        }
        struct BufferView: Decodable {
            let buffer: Int
            let byteOffset: Int?
            let byteLength: Int
            let byteStride: Int?
        }
        struct BufferDef: Decodable {
            let byteLength: Int
            let uri: String?
        }
        struct MaterialDef: Decodable {
            let name: String?
            let pbrMetallicRoughness: PBR?
            let doubleSided: Bool?
        }
        struct PBR: Decodable {
            let baseColorFactor: [Float]?
            let baseColorTexture: TextureRef?
        }
        struct TextureRef: Decodable { let index: Int }
        struct TextureDef: Decodable { let source: Int? }
        struct ImageDef: Decodable {
            let uri: String?
            let mimeType: String?
            let bufferView: Int?
        }

        let asset: Asset
        let scene: Int?
        let scenes: [SceneDef]?
        let nodes: [NodeDef]?
        let meshes: [MeshDef]?
        let accessors: [Accessor]?
        let bufferViews: [BufferView]?
        let buffers: [BufferDef]?
        let materials: [MaterialDef?]?
        let textures: [TextureDef]?
        let images: [ImageDef]?
    }
}
