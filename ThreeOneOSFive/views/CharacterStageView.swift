import SwiftUI
import SceneKit
import UIKit

/// The two real character meshes shipped in `CharacterModels/`.
enum HeroCharacterModel: String, CaseIterable, Identifiable, Hashable {
    case rouk
    case sakura

    var id: String { rawValue }

    /// Full name used by VoiceOver and the picker.
    var displayName: String {
        switch self {
        case .rouk: return "ROUK"
        case .sakura: return "GOLDEN SAKURA"
        }
    }

    /// Compact name for the hero switcher.
    var shortName: String {
        switch self {
        case .rouk: return "ROUK"
        case .sakura: return "SAKURA"
        }
    }

    var objectFile: String { "\(rawValue).obj" }

    /// Folder reference in the app bundle: `CharacterVault/<rawValue>/`.
    /// The vault holds sealed blobs and unlocks them into caches on first use.
    var objectURL: URL? {
        CharacterVault.modelURL(self)
    }
}

/// Live SceneKit stage for the home hero. The mesh is loaded with SceneKit,
/// normalised to a one-unit height and shown with a close, softly lit turntable
/// view. Auto-rotation pauses while the user drags and stays off under Reduce
/// Motion.
struct CharacterStageView: UIViewRepresentable {
    let model: HeroCharacterModel
    let reduceMotion: Bool
    let isActive: Bool
    /// The home hero turns on its own. The patch body map needs a fixed pose so
    /// a callout always points at the same anatomy, so it passes `false`.
    var turntable: Bool = true

    func makeUIView(context: Context) -> CharacterSceneView {
        let view = CharacterSceneView(frame: .zero)
        view.apply(model: model, reduceMotion: reduceMotion, isActive: isActive, turntable: turntable)
        return view
    }

    func updateUIView(_ uiView: CharacterSceneView, context: Context) {
        uiView.apply(model: model, reduceMotion: reduceMotion, isActive: isActive, turntable: turntable)
    }
}

final class CharacterSceneView: SCNView, UIGestureRecognizerDelegate {
    private let stageScene = SCNScene()
    private let cameraNode = SCNNode()
    private let modelContainer = SCNNode()
    private var modelCache: [HeroCharacterModel: SCNNode] = [:]

    private var requestedModel: HeroCharacterModel?
    private var loadToken = UUID()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var baseYaw: Float = 0
    private var dragYaw: Float = 0
    private var idleYaw: Float = 0
    private var idleSpeed: Float = 0
    private var idleTime: CFTimeInterval = 0
    private var isDragging = false
    private var reduceMotion = false
    private var isActive = false
    private var turntable = true

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        rendersContinuously = false
        isPlaying = false
        allowsCameraControl = false
        autoenablesDefaultLighting = false
        scene = stageScene

        stageScene.background.contents = UIColor.clear
        stageScene.lightingEnvironment.contents = UIColor(
            red: 0.25,
            green: 0.31,
            blue: 0.43,
            alpha: 1
        )
        stageScene.lightingEnvironment.intensity = 0.72
        stageScene.rootNode.addChildNode(cameraNode)
        stageScene.rootNode.addChildNode(modelContainer)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2.2)
        pointOfView = cameraNode

        addLight(
            type: .ambient,
            color: UIColor(red: 0.48, green: 0.57, blue: 0.72, alpha: 1),
            intensity: 180,
            position: nil
        )
        addLight(
            type: .directional,
            color: UIColor(red: 1.0, green: 0.91, blue: 0.79, alpha: 1),
            intensity: 1_050,
            position: SCNVector3(2.4, 3.8, 4.6)
        )
        addLight(
            type: .directional,
            color: UIColor(red: 0.42, green: 0.66, blue: 1.0, alpha: 1),
            intensity: 520,
            position: SCNVector3(-3.2, 1.8, 2.8)
        )
        addLight(
            type: .directional,
            color: UIColor(red: 0.30, green: 0.78, blue: 1.0, alpha: 1),
            intensity: 820,
            position: SCNVector3(-2.4, 3.0, -4.2)
        )

        // The updated hero has no copy over the stage, so the character stays
        // centred and the switcher lives in the top-right corner.
        modelContainer.position = SCNVector3Zero

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    private func addLight(type: SCNLight.LightType, color: UIColor, intensity: CGFloat, position: SCNVector3?) {
        let light = SCNLight()
        light.type = type
        light.color = color
        light.intensity = intensity
        light.castsShadow = false
        let node = SCNNode()
        node.light = light
        if let position = position {
            node.position = position
            node.look(at: SCNVector3Zero)
        }
        stageScene.rootNode.addChildNode(node)
    }

    func apply(model: HeroCharacterModel, reduceMotion: Bool, isActive: Bool, turntable: Bool = true) {
        self.reduceMotion = reduceMotion
        self.isActive = isActive
        self.turntable = turntable

        if requestedModel != model {
            requestedModel = model
            load(model)
        }

        if reduceMotion || !turntable {
            idleYaw = 0
            idleSpeed = 0
        }
        updateDisplayLink()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCamera()
    }

    private func updateCamera() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fovY = 30.0 * Double.pi / 180.0
        let aspect = Double(bounds.width / bounds.height)
        // The imported meshes are normalised to 1 unit tall. Leave comfortable
        // head/foot margin inside the square card instead of filling the frame.
        let distanceV = 0.76 / tan(fovY / 2)
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let distanceH = 0.48 / tan(fovX / 2)
        cameraNode.position = SCNVector3(0, 0, Float(max(distanceV, distanceH)))
        cameraNode.look(at: SCNVector3Zero)
    }

    private func load(_ model: HeroCharacterModel) {
        if let cached = modelCache[model] {
            install(cached)
            return
        }

        guard let url = model.objectURL else {
            log("hero: \(model.objectFile) missing from the bundle")
            return
        }

        let token = UUID()
        loadToken = token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let imported: SCNScene
            do {
                imported = try SCNScene(url: url, options: nil)
            } catch {
                log("hero: \(model.objectFile) could not be imported — \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                let root = SCNNode()
                for child in imported.rootNode.childNodes {
                    root.addChildNode(child)
                }
                guard root.childNodes.isEmpty == false else {
                    log("hero: \(model.objectFile) produced no renderable nodes")
                    return
                }
                self.prepare(root)
                self.modelCache[model] = root
                self.install(root)
            }
        }
    }

    private func prepare(_ root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.isDoubleSided = true
                material.lightingModel = .physicallyBased
                material.diffuse.intensity = 1.0
                material.metalness.contents = NSNumber(value: 0.03)
                material.roughness.contents = NSNumber(value: 0.68)
            }
        }

        guard let (minimum, maximum) = geometryBounds(of: root) else {
            log("hero: character geometry has no bounds")
            return
        }
        let height = maximum.y - minimum.y
        guard height > 0 else {
            log("hero: character geometry has zero height")
            return
        }
        let scale = 1.0 / height
        root.scale = SCNVector3(scale, scale, scale)
        root.position = SCNVector3(
            -(minimum.x + maximum.x) * 0.5 * scale,
            -(minimum.y + maximum.y) * 0.5 * scale,
            -(minimum.z + maximum.z) * 0.5 * scale
        )
    }

    /// `SCNNode.boundingBox` only covers the node's own geometry, so the union
    /// is built from every mesh and mapped into the root's space. The OBJ
    /// exports keep the body parts in sibling nodes, not one merged mesh.
    private func geometryBounds(
        of root: SCNNode
    ) -> (minimum: SCNVector3, maximum: SCNVector3)? {
        var minimum = SCNVector3(Float.greatestFiniteMagnitude,
                                 Float.greatestFiniteMagnitude,
                                 Float.greatestFiniteMagnitude)
        var maximum = SCNVector3(-Float.greatestFiniteMagnitude,
                                 -Float.greatestFiniteMagnitude,
                                 -Float.greatestFiniteMagnitude)
        var found = false

        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (localMin, localMax) = node.boundingBox
            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMax.z)
            ]
            for corner in corners {
                let point = node.convertPosition(corner, to: root)
                minimum.x = min(minimum.x, point.x)
                minimum.y = min(minimum.y, point.y)
                minimum.z = min(minimum.z, point.z)
                maximum.x = max(maximum.x, point.x)
                maximum.y = max(maximum.y, point.y)
                maximum.z = max(maximum.z, point.z)
                found = true
            }
        }

        return found ? (minimum, maximum) : nil
    }

    private func install(_ root: SCNNode) {
        modelContainer.childNodes.forEach { $0.removeFromParentNode() }
        baseYaw = turntable ? -0.20 : 0
        dragYaw = 0
        idleYaw = 0
        idleSpeed = 0
        idleTime = 0
        root.eulerAngles = SCNVector3Zero
        root.opacity = 0
        modelContainer.addChildNode(root)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.42
        root.opacity = 1
        SCNTransaction.commit()
    }

    private func updateDisplayLink() {
        let shouldRun = isActive && window != nil
        if shouldRun, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
            rendersContinuously = true
            isPlaying = true
        } else if !shouldRun, displayLink != nil {
            displayLink?.invalidate()
            displayLink = nil
            rendersContinuously = false
            isPlaying = false
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let delta: Float
        if lastTimestamp == 0 {
            delta = 1.0 / 30.0
        } else {
            delta = Float(min(link.targetTimestamp - link.timestamp, 1.0 / 15.0))
        }
        lastTimestamp = link.timestamp

        if !reduceMotion, turntable, !isDragging {
            idleTime += Double(delta)
            let target: Float = idleTime > 0.7 ? 0.34 : 0
            idleSpeed += (target - idleSpeed) * min(1, delta * 1.8)
        } else {
            idleSpeed = 0
            if reduceMotion || !turntable { idleYaw = 0 }
        }
        idleYaw += idleSpeed * delta

        let gentleSway = reduceMotion || !turntable ? 0 : Float(sin(link.timestamp * 0.48) * 0.016)
        modelContainer.eulerAngles = SCNVector3(
            gentleSway,
            baseYaw + dragYaw + idleYaw,
            0
        )
        let bob = reduceMotion || !turntable ? 0 : Float(sin(link.timestamp * 0.9) * 0.0035)
        modelContainer.position.y = bob
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            isDragging = true
            idleTime = 0
        case .changed:
            let translation = pan.translation(in: self)
            pan.setTranslation(.zero, in: self)
            dragYaw += Float(translation.x) * 0.012
            idleTime = 0
        case .ended, .cancelled, .failed:
            isDragging = false
            idleTime = 0
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let translation = pan.translation(in: self)
        return abs(translation.x) > abs(translation.y) * 1.15
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
