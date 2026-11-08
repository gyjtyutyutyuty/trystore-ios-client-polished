import SwiftUI
import SceneKit
import ModelIO
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

    /// Folder reference in the app bundle: `CharacterModels/<rawValue>/`.
    var objectURL: URL? {
        Bundle.main.url(
            forResource: rawValue,
            withExtension: "obj",
            subdirectory: "CharacterModels/\(rawValue)"
        ) ?? Bundle.main.url(forResource: rawValue, withExtension: "obj")
    }
}

/// Live SceneKit stage for the home hero. The mesh is loaded with Model I/O,
/// normalised to a one-unit height, and kept at a fixed camera distance so the
/// character reads the same on every screen. Auto-rotation pauses while the
/// user drags and stays off under Reduce Motion.
struct CharacterStageView: UIViewRepresentable {
    let model: HeroCharacterModel
    let reduceMotion: Bool
    let isActive: Bool

    func makeUIView(context: Context) -> CharacterSceneView {
        let view = CharacterSceneView()
        view.apply(model: model, reduceMotion: reduceMotion, isActive: isActive)
        return view
    }

    func updateUIView(_ uiView: CharacterSceneView, context: Context) {
        uiView.apply(model: model, reduceMotion: reduceMotion, isActive: isActive)
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
        preferredFramesPerSecond = 30
        rendersContinuously = false
        isPlaying = false
        allowsCameraControl = false
        autoenablesDefaultLighting = false
        scene = stageScene

        stageScene.background.contents = UIColor.clear
        stageScene.rootNode.addChildNode(cameraNode)
        stageScene.rootNode.addChildNode(modelContainer)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2.2)
        pointOfView = cameraNode

        addLight(
            type: .ambient,
            color: UIColor(red: 0.42, green: 0.50, blue: 0.62, alpha: 1),
            intensity: 360,
            position: nil
        )
        addLight(
            type: .directional,
            color: UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1),
            intensity: 880,
            position: SCNVector3(2.6, 3.6, 4.2)
        )
        addLight(
            type: .directional,
            color: UIColor(red: 0.22, green: 0.62, blue: 1.0, alpha: 1),
            intensity: 330,
            position: SCNVector3(-3.2, 1.2, 2.6)
        )
        addLight(
            type: .directional,
            color: UIColor(red: 0.36, green: 0.82, blue: 1.0, alpha: 1),
            intensity: 620,
            position: SCNVector3(-2.2, 2.8, -4.0)
        )
        addLight(
            type: .directional,
            color: UIColor(red: 0.16, green: 0.42, blue: 0.76, alpha: 1),
            intensity: 220,
            position: SCNVector3(0.6, -2.8, 2.0)
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

    func apply(model: HeroCharacterModel, reduceMotion: Bool, isActive: Bool) {
        self.reduceMotion = reduceMotion
        self.isActive = isActive

        if requestedModel != model {
            requestedModel = model
            load(model)
        }

        if reduceMotion {
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
        let distanceV = 0.54 / tan(fovY / 2)
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let distanceH = 0.38 / tan(fovX / 2)
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
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            guard asset.count > 0 else {
                log("hero: \(model.objectFile) could not be imported")
                return
            }
            let imported = SCNScene(mdlAsset: asset)
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
                material.lightingModel = .blinn
                material.diffuse.intensity = 1.0
                material.ambient.intensity = 0.42
                material.specular.intensity = 0.08
                material.shininess = 0.12
                material.locksAmbientWithDiffuse = true
            }
        }

        var minimum = SCNVector3Zero
        var maximum = SCNVector3Zero
        guard root.getBoundingBoxMin(&minimum, &maximum) else {
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

    private func install(_ root: SCNNode) {
        modelContainer.childNodes.forEach { $0.removeFromParentNode() }
        baseYaw = 0
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
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
            isPlaying = true
        } else if !shouldRun, displayLink != nil {
            displayLink?.invalidate()
            displayLink = nil
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

        if !reduceMotion, !isDragging {
            idleTime += Double(delta)
            let target: Float = idleTime > 1.6 ? 0.26 : 0
            idleSpeed += (target - idleSpeed) * min(1, delta * 2.4)
        } else {
            idleSpeed = 0
            if reduceMotion { idleYaw = 0 }
        }
        idleYaw += idleSpeed * delta

        modelContainer.eulerAngles.y = baseYaw + dragYaw + idleYaw
        let bob = reduceMotion ? 0 : Float(sin(link.timestamp * 1.1) * 0.006)
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

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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
