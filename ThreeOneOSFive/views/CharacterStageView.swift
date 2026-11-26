import SwiftUI
import SceneKit
import UIKit

/// The two real character meshes. Debug builds may read `CharacterModels/`;
/// Release builds materialize them from the licensed character vault.
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

    /// Feed folder materialized into Caches: `CharacterVault/<rawValue>/`.
    /// The sealed source is downloaded after the feed releases the key.
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
    /// Downloaded garment meshes that follow the body. Empty on the home hero.
    var garments: [PlayerGarment] = []
    /// A complete FFHub export. Its GLB carries the body the pieces were
    /// fitted to, so the stage shows it as the whole figure.
    var outfit: WornOutfit? = nil

    func makeUIView(context: Context) -> CharacterSceneView {
        let view = CharacterSceneView(frame: .zero)
        view.apply(
            model: model,
            reduceMotion: reduceMotion,
            isActive: isActive,
            turntable: turntable,
            garments: garments,
            outfit: outfit
        )
        return view
    }

    func updateUIView(_ uiView: CharacterSceneView, context: Context) {
        uiView.apply(
            model: model,
            reduceMotion: reduceMotion,
            isActive: isActive,
            turntable: turntable,
            garments: garments,
            outfit: outfit
        )
    }
}

/// A parsed character plus the submeshes that carry its baked-in outfit. The
/// bundled OBJ exports keep skin, torso, legs, shoes, head and hair as separate
/// objects, so a downloaded garment can replace the clothing layer for its slot
/// instead of being drawn on top of the old clothes.
private final class CharacterBody {
    let root: SCNNode
    var layers: [(node: SCNNode, slot: PlayerOutfitSlot)] = []

    init(root: SCNNode) {
        self.root = root
    }
}

final class CharacterSceneView: SCNView, UIGestureRecognizerDelegate {
    private let stageScene = SCNScene()
    private let cameraNode = SCNNode()
    private let modelContainer = SCNNode()
    /// Garments hang off the same container as the body, so the turntable
    /// turns them together. The body root is swapped on model change; this
    /// node survives the swap.
    private let garmentContainer = SCNNode()
    /// A complete FFHub export hangs here instead of on the body. Its body is
    /// already inside the GLB, so the bundled character steps aside while it
    /// is worn.
    private let outfitContainer = SCNNode()
    private var bodyRoot: CharacterBody?
    private var modelCache: [HeroCharacterModel: CharacterBody] = [:]
    /// Clothing submeshes of the body currently on screen, and the slots whose
    /// replacement mesh actually arrived. A layer is only hidden once its slot
    /// has a garment, so a failed download never leaves the character bare.
    private var bodyLayers: [(node: SCNNode, slot: PlayerOutfitSlot)] = []
    private var wornSlots: Set<PlayerOutfitSlot> = []

    private var requestedModel: HeroCharacterModel?
    private var loadToken = UUID()

    private var appliedGarments: [PlayerGarment] = []
    private var garmentToken = UUID()

    private var appliedOutfit: WornOutfit?
    private var outfitToken = UUID()

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
        let constrained = AppPerformance.isConstrained
        backgroundColor = .clear
        isOpaque = false
        // A 2–3 GB phone fills the hero at 60 fps with 4x MSAA, HDR and PBR.
        // The lean path keeps the silhouette and drops the per-pixel work.
        antialiasingMode = constrained ? .none : .multisampling4X
        preferredFramesPerSecond = constrained ? 30 : 60
        contentScaleFactor = constrained ? min(UIScreen.main.scale, 2) : UIScreen.main.scale
        rendersContinuously = false
        // On-demand rendering: SceneKit redraws when the scene graph changes.
        // Leaving isPlaying false meant a fixed pose (or a stage whose display
        // link had not started yet) could keep an added mesh off screen.
        isPlaying = true
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
        modelContainer.addChildNode(garmentContainer)
        modelContainer.addChildNode(outfitContainer)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = !constrained
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bundleKeyDidChange),
            name: .patchBundleKeyDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vaultDidChange),
            name: .characterVaultDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    func apply(
        model: HeroCharacterModel,
        reduceMotion: Bool,
        isActive: Bool,
        turntable: Bool = true,
        garments: [PlayerGarment] = [],
        outfit: WornOutfit? = nil
    ) {
        self.reduceMotion = reduceMotion
        self.isActive = isActive
        self.turntable = turntable

        if requestedModel != model {
            requestedModel = model
            load(model)
        }

        if outfit != appliedOutfit {
            appliedOutfit = outfit
            rebuildOutfit()
        }

        if garments != appliedGarments {
            appliedGarments = garments
            rebuildGarments()
        }

        if reduceMotion || !turntable {
            idleYaw = 0
            idleSpeed = 0
        }
        updateDisplayLink()
    }

    // MARK: Garments

    /// Parses each cached GLB off the main thread, then hangs the meshes on the
    /// body. The loader is cheap but ten outfits still add up, and the stage
    /// is already animating.
    private func rebuildGarments() {
        garmentContainer.childNodes.forEach { $0.removeFromParentNode() }
        wornSlots.removeAll()
        applyBodyLayers()
        updateBodyVisibility()

        let wanted = appliedGarments
        guard !wanted.isEmpty else {
            setNeedsDisplay()
            return
        }

        let token = UUID()
        garmentToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var loaded: [(PlayerGarment, GarmentModel)] = []
            for garment in wanted {
                guard let model = try? GLBSceneLoader.model(from: garment.url) else { continue }
                loaded.append((garment, model))
            }

            DispatchQueue.main.async {
                guard let self, self.garmentToken == token else { return }
                for (garment, model) in loaded {
                    self.attach(model, slot: garment.slot, id: garment.id)
                }
                self.updateBodyVisibility()
                self.setNeedsDisplay()
            }
        }
    }

    private func attach(_ model: GarmentModel, slot: PlayerOutfitSlot, id: String) {
        guard let fit = slot.garmentFit, model.height > 0.001 else { return }

        // Height-driven, not longest-side-driven: a jacket is wider across the
        // sleeves than it is tall, so dividing by its arm span made every
        // sleeved item come out short and lose the body.
        let scale = fit.height / model.height
        let holder = SCNNode()
        holder.name = "garment-\(id)"
        holder.addChildNode(model.node)
        // Uniform on every axis: resizing a downloaded garment to its slot must
        // never stretch it wider or deeper than the scan the player downloaded.
        holder.scale = SCNVector3(Float(scale), Float(scale), Float(scale))
        holder.position = SCNVector3(0, Float(fit.centerY), Float(fit.z))
        garmentContainer.addChildNode(holder)

        wornSlots.insert(slot)
        applyBodyLayers()
    }

    /// Hides the body's own top, trousers or shoes for every slot that is now
    /// covered by a downloaded mesh.
    private func applyBodyLayers() {
        for layer in bodyLayers {
            layer.node.isHidden = wornSlots.contains(layer.slot)
        }
    }

    // MARK: Full outfit

    /// Parses an FFHub export off the main thread and stands it in for the
    /// bundled character. The export is one figure, already aligned to its
    /// own body, so it is scaled uniformly to the stage's one-unit height.
    private func rebuildOutfit() {
        let token = UUID()
        outfitToken = token

        outfitContainer.childNodes.forEach { $0.removeFromParentNode() }
        updateBodyVisibility()

        guard let wanted = appliedOutfit else {
            setNeedsDisplay()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let model = try? GLBSceneLoader.model(from: wanted.url)

            DispatchQueue.main.async {
                guard let self, self.outfitToken == token,
                      let model, model.height > 0.001 else { return }

                let holder = SCNNode()
                holder.name = "outfit-\(wanted.id)"
                holder.addChildNode(model.node)
                let scale = 1 / model.height
                holder.scale = SCNVector3(Float(scale), Float(scale), Float(scale))
                self.outfitContainer.addChildNode(holder)
                self.updateBodyVisibility()
                self.setNeedsDisplay()
            }
        }
    }

    /// The bundled body and the per-slot garments only make sense while no
    /// complete outfit is on. Hiding them keeps the stage to one figure.
    private func updateBodyVisibility() {
        let fullOutfit = !outfitContainer.childNodes.isEmpty
        bodyRoot?.root.isHidden = fullOutfit
        garmentContainer.isHidden = fullOutfit
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

    /// The first launch can draw the home stage before the feed releases the
    /// vault key. Retry the mesh once the key lands instead of leaving an
    /// empty stage until the next app launch.
    @objc private func bundleKeyDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.requestedModel,
                  self.modelCache[model] == nil else { return }
            self.requestedModel = nil
            self.load(model)
            self.requestedModel = model
        }
    }

    /// The vault arrives after the bundle key on a fresh install. Reload the
    /// hero once the sealed blobs have landed.
    @objc private func vaultDidChange() {
        bundleKeyDidChange()
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
                let body = CharacterBody(root: root)
                self.prepare(body)
                self.modelCache[model] = body
                self.install(body)
            }
        }
    }

    private func prepare(_ body: CharacterBody) {
        let root = body.root
        let constrained = AppPerformance.isConstrained
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.isDoubleSided = true
                material.lightingModel = constrained ? .blinn : .physicallyBased
                material.diffuse.intensity = 1.0
                material.metalness.contents = NSNumber(value: constrained ? 0 : 0.03)
                material.roughness.contents = NSNumber(value: 0.68)
            }
        }

        guard let (minimum, maximum) = Self.geometryBounds(of: root, in: root) else {
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

        body.layers = Self.clothingLayers(in: root, minimum: minimum, height: height)
    }

    /// The torso, trouser and shoe submeshes, found by their vertical band. The
    /// bands are fractions of the normalised body height, so they hold for both
    /// bundled characters. Head, hair and the skin mesh are never classified:
    /// hiding those would remove body, not clothes.
    private static func clothingLayers(
        in root: SCNNode,
        minimum: SCNVector3,
        height: Float
    ) -> [(node: SCNNode, slot: PlayerOutfitSlot)] {
        guard height > 0 else { return [] }

        var layers: [(node: SCNNode, slot: PlayerOutfitSlot)] = []
        for child in root.childNodes {
            guard child.geometry != nil || !child.childNodes.isEmpty else { continue }
            guard let bounds = geometryBounds(of: child, in: root) else { continue }

            let low = CGFloat((bounds.minimum.y - minimum.y) / height)
            let high = CGFloat((bounds.maximum.y - minimum.y) / height)
            guard let slot = clothingSlot(lowY: low, highY: high) else { continue }
            layers.append((child, slot))
        }
        return layers
    }

    private static func clothingSlot(lowY: CGFloat, highY: CGFloat) -> PlayerOutfitSlot? {
        // One unit of body height. A mesh covering nearly all of it is the skin.
        if highY - lowY > 0.85 { return nil }
        // Soft feet layer at ground level.
        if highY <= 0.15 { return .shoes }
        // Waist to ankle: the trousers. Rouk 0.02...0.59, Sakura 0.07...0.57.
        if lowY <= 0.22, (0.40...0.75).contains(highY) { return .pants }
        // Waist to shoulders: the top. Rouk 0.54...0.86, Sakura 0.51...0.85.
        if (0.45..<0.62).contains(lowY), (0.75...0.92).contains(highY) { return .top }
        return nil
    }

    /// `SCNNode.boundingBox` only covers the node's own geometry, so the union
    /// is built from every mesh and mapped into the root's space. The OBJ
    /// exports keep the body parts in sibling nodes, not one merged mesh.
    private static func geometryBounds(
        of subtree: SCNNode,
        in space: SCNNode
    ) -> (minimum: SCNVector3, maximum: SCNVector3)? {
        var minimum = SCNVector3(Float.greatestFiniteMagnitude,
                                 Float.greatestFiniteMagnitude,
                                 Float.greatestFiniteMagnitude)
        var maximum = SCNVector3(-Float.greatestFiniteMagnitude,
                                 -Float.greatestFiniteMagnitude,
                                 -Float.greatestFiniteMagnitude)
        var found = false

        subtree.enumerateHierarchy { node, _ in
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
                let point = node.convertPosition(corner, to: space)
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

    private func install(_ body: CharacterBody) {
        bodyRoot?.root.removeFromParentNode()
        bodyRoot = body
        bodyLayers = body.layers
        let root = body.root
        baseYaw = turntable ? -0.20 : 0
        dragYaw = 0
        idleYaw = 0
        idleSpeed = 0
        idleTime = 0
        root.eulerAngles = SCNVector3Zero

        // Opacity 0 plus an implicit fade only works while the renderer is
        // advancing scene time. A fixed-pose stage keeps `isPlaying` false, so
        // the mesh stayed transparent forever. Be visible first, fade only when
        // the display link is actually running.
        root.opacity = 1
        modelContainer.addChildNode(root)
        applyBodyLayers()
        updateBodyVisibility()
        if displayLink != nil {
            root.opacity = 0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.42
            root.opacity = 1
            SCNTransaction.commit()
        }

        updateDisplayLink()
        setNeedsDisplay()
    }

    private func updateDisplayLink() {
        // A fixed pose (the patch body map) only needs frames while a finger is
        // turning it. The old link kept rendering a still image at 60 fps.
        let isAnimating = turntable && !reduceMotion
        let shouldRun = isActive && window != nil && (isAnimating || isDragging)
        if shouldRun, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = AppPerformance.isConstrained ? 30 : 60
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
            rendersContinuously = true
        } else if !shouldRun, displayLink != nil {
            displayLink?.invalidate()
            displayLink = nil
            rendersContinuously = false
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
            updateDisplayLink()
        case .changed:
            let translation = pan.translation(in: self)
            pan.setTranslation(.zero, in: self)
            dragYaw += Float(translation.x) * 0.012
            idleTime = 0
        case .ended, .cancelled, .failed:
            isDragging = false
            idleTime = 0
            updateDisplayLink()
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
