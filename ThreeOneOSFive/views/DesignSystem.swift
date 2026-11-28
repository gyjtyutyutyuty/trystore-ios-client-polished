import SwiftUI
import UIKit
import AVFoundation
import CoreMotion
import Combine

/// Dark exhibition surfaces. The token names are preserved for existing call
/// sites; values follow Apple's charcoal palette and TryStore's logo-blue accent.
enum AppPalette {
    static let canvas = Color.black                         // #000000
    static let surface = Color(red: 0.055, green: 0.055, blue: 0.055) // #0e0e0e
    static let raised = Color(red: 0.114, green: 0.114, blue: 0.122) // #1d1d1f
    static let hairline = Color(red: 0.200, green: 0.200, blue: 0.212) // #333336

    static let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969) // #f5f5f7
    static let textSecondary = Color(red: 0.800, green: 0.800, blue: 0.800) // #cccccc
    static let textTertiary = Color(red: 0.525, green: 0.525, blue: 0.545) // #86868b

    /// TryStore logo blue: interactive and active-state accent.
    static let brand = Color(red: 0.0, green: 0.702, blue: 1.0) // neon #00B3FF, the logo blue pushed to full saturation
    /// Legacy aliases retained while existing screens share the same accent.
    static let mint = brand
    static let blue = brand
    static let amber = Color(red: 1.0, green: 0.776, blue: 0.427) // accessible warning state; logo blue remains the brand accent
    static let coral = Color(red: 1.0, green: 0.576, blue: 0.541)
}

/// 4 pt spacing grid. Screen inset, panel padding and section gaps all come
/// from this scale so vertical rhythm stays consistent between screens.
enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let screenInset: CGFloat = 20
    /// iOS 26 draws the tab bar over scroll content; this is the clearance
    /// that keeps the last card above it.
    static let tabBarClearance: CGFloat = 88
}

/// The tier below "everything animates". A 2–3 GB or low-core phone spends its
/// frame budget on the SceneKit stage, so the interface drops continuous tilt,
/// multi-sample AA and the reveal blur before it drops frames.
enum AppPerformance {
    static var isConstrained: Bool {
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return true }
        if info.physicalMemory <= 3 * 1_024 * 1_024 * 1_024 { return true }
        if info.processorCount <= 5 { return true }
        return false
    }
}

private struct AppPerformanceModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the hardware or Low Power Mode asks for the lean render path.
    var appPerformanceMode: Bool {
        get { self[AppPerformanceModeKey.self] }
        set { self[AppPerformanceModeKey.self] = newValue }
    }
}

enum AppRadius {
    static let chip: CGFloat = 10
    static let control: CGFloat = 18
    static let tile: CGFloat = 28
    static let panel: CGFloat = 28
    static let hero: CGFloat = 28
}

/// Short, purposeful timings. Controls answer in ~140 ms, panels in ~280 ms.
enum AppMotion {
    static let micro: Double = 0.14
    static let control: Double = 0.20
    static let panel: Double = 0.28

    static var tile: Animation { .spring(response: 0.30, dampingFraction: 0.86) }
    static var surface: Animation { .spring(response: 0.34, dampingFraction: 0.92) }
    static var settle: Animation { .spring(response: 0.46, dampingFraction: 0.95) }

    static func reveal(delay: Double) -> Animation {
        .spring(response: 0.50, dampingFraction: 0.94).delay(delay)
    }
}

/// Quiet SF-style hierarchy, scaled with UIFontMetrics for Dynamic Type.
enum AppType {
    static func hero(_ compact: Bool) -> Font {
        scaled(compact ? 34 : 44, weight: .semibold, textStyle: .largeTitle)
    }
    static func display() -> Font { scaled(28, weight: .semibold, textStyle: .title2) }

    /// HUD chrome keeps the mock's compact geometry but is still routed through
    /// UIFontMetrics, so the control deck follows the user's text size.
    static func hudWordmark(compact: Bool) -> Font {
        scaled(compact ? 25 : 31, weight: .heavy, textStyle: .title2)
    }
    static func hudTagline() -> Font { scaled(9, weight: .bold, textStyle: .caption2) }
    static func hudStageTitle() -> Font { scaled(11, weight: .heavy, textStyle: .caption1) }
    static func hudSegment() -> Font { scaled(10, weight: .heavy, textStyle: .caption2) }
    static func hudCallout() -> Font { scaled(10, weight: .heavy, textStyle: .caption2) }
    static func hudTitle() -> Font { scaled(19, weight: .heavy, textStyle: .headline) }
    static func hudKicker() -> Font { scaled(10, weight: .bold, textStyle: .caption2) }
    static func hudMetricLabel() -> Font { scaled(10, weight: .semibold, textStyle: .caption2) }
    static func hudMetricValue() -> Font { scaled(15, weight: .bold, textStyle: .subheadline) }
    static func hudChip() -> Font { scaled(11, weight: .heavy, textStyle: .caption1) }
    static func hudHint() -> Font { scaled(12, weight: .medium, textStyle: .footnote) }
    static func hudTab() -> Font { scaled(9, weight: .bold, textStyle: .caption2) }
    static func section() -> Font { scaled(19, weight: .semibold, textStyle: .headline) }
    static func label() -> Font { scaled(12, weight: .regular, textStyle: .caption1) }
    static func body() -> Font { scaled(14, weight: .regular, textStyle: .body) }
    static func value() -> Font { scaled(17, weight: .semibold, textStyle: .body) }
    static func meta() -> Font { scaled(12, weight: .regular, textStyle: .footnote) }

    /// Readings are data, not prose. They stay monospaced and unscaled so gauges,
    /// tabular columns and the progress ring keep their geometry while every
    /// label around them grows with the user's text size.
    static func digits(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Each size is routed through UIFontMetrics, so the whole interface follows
    /// Settings > Display & Brightness > Text Size instead of pinning every label
    /// to a fixed point size. The root clamps the range so fixed-height controls
    /// (44 pt targets, gauge rings) keep their shape at the largest settings.
    private static func scaled(
        _ size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let dynamic = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        let roundedDescriptor = dynamic.fontDescriptor.withDesign(.rounded) ?? dynamic.fontDescriptor
        return Font(UIFont(descriptor: roundedDescriptor, size: dynamic.pointSize))
    }
}

enum AppTheme {
    static let accent = AppPalette.brand
    static let accentSecondary = AppPalette.brand
    static let pageBackground = AppPalette.canvas
    static let consoleBackground = AppPalette.surface
    static let referenceCard = AppPalette.raised
    static let cardBorder = Color.white.opacity(0.10)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
}

/// One looping player for the whole app. A `TabView` keeps every tab alive, so
/// giving each backdrop its own player decoded the same clip several times at
/// once. The storm carries its own ambience and mixes with the user's audio.
final class StormLoopVideo {
    static let shared = StormLoopVideo()

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observers: [NSObjectProtocol] = []

    private init() {
        player.isMuted = false
        player.volume = 0.85
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)

        guard let url = Self.url else { return }
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.player.play()
            }
        )
        observers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.player.pause()
            }
        )

        player.play()
    }

    /// The clip ships as a data set so the Xcode resource phase stays as it is.
    /// `AVPlayer` needs a file URL, so the bytes are materialised in Caches once
    /// per install.
    static var url: URL? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let destination = directory.appendingPathComponent("StormLoop-v5.mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        guard let asset = NSDataAsset(name: "StormLoop") else { return nil }
        do {
            try asset.data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

final class StormLoopLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = StormLoopVideo.shared.player
    }
}

struct StormLoopVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> StormLoopLayerView {
        StormLoopLayerView(frame: .zero)
    }

    func updateUIView(_ uiView: StormLoopLayerView, context: Context) {}
}

/// Home's hero clip. It uses the same data-set materialisation as the storm
/// loop but its own player, so it can pause as soon as Home leaves the screen.
final class HologramaHeroVideo {
    static let shared = HologramaHeroVideo()

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observers: [NSObjectProtocol] = []
    private var isVisible = false

    private init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false

        guard let url = Self.url else { return }
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.player.play()
            }
        )
        observers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.player.pause()
            }
        )
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            player.play()
        } else {
            player.pause()
        }
    }

    /// The clip ships as a data set so the Xcode resource phase stays as it is.
    /// `AVPlayer` needs a file URL, so the bytes are materialised in Caches once
    /// per install.
    static var url: URL? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let destination = directory.appendingPathComponent("HologramaHero-v2.mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        guard let asset = NSDataAsset(name: "HologramaHero") else { return nil }
        do {
            try asset.data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

final class HologramaHeroLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = HologramaHeroVideo.shared.player
    }
}

struct HologramaHeroVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> HologramaHeroLayerView {
        HologramaHeroLayerView(frame: .zero)
    }

    func updateUIView(_ uiView: HologramaHeroLayerView, context: Context) {}
}

/// A cinematic gameplay backdrop for Home. The grade keeps the HUD crop dark
/// enough for the control deck while leaving the hologram effects readable.
struct HologramaHeroBackdrop: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppPalette.canvas
                if reduceMotion || performanceMode {
                    Image("HologramaHeroStill")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    HologramaHeroVideoView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .onAppear { HologramaHeroVideo.shared.setVisible(true) }
                        .onDisappear { HologramaHeroVideo.shared.setVisible(false) }
                }
                LinearGradient(
                    stops: [
                        .init(color: AppPalette.canvas.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.26),
                        .init(color: .clear, location: 0.58),
                        .init(color: AppPalette.canvas.opacity(0.35), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private enum StormBackdropTone {
    static let deep = Color(red: 0.010, green: 0.043, blue: 0.098)
    static let mid = Color(red: 0.016, green: 0.118, blue: 0.255)
    static let horizon = Color(red: 0.024, green: 0.267, blue: 0.475)
}

/// The app-wide backdrop: the blue lightning film plays full-screen, with the
/// logo-blue grade, vignette and chrome scrims keeping the panels readable. The
/// film carries its own real thunder and rain; Reduce Motion swaps in a still.
struct AppPremiumBackdrop: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: StormBackdropTone.deep, location: 0),
                        .init(color: StormBackdropTone.mid, location: 0.52),
                        .init(color: StormBackdropTone.horizon, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [AppPalette.brand.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: proxy.size.width * 1.15
                )

                if reduceMotion {
                    Image("StormLoopStill")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    StormLoopVideoView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(0.94)
                }

                if !reduceMotion && !performanceMode {
                    StormAuroraView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blendMode(.plusLighter)
                        .opacity(0.30)
                } else {
                    RadialGradient(
                        colors: [AppPalette.brand.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.95
                    )
                }

                RadialGradient(
                    colors: [.clear, StormBackdropTone.deep.opacity(0.58)],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.24,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.78
                )

                LinearGradient(
                    stops: [
                        .init(color: StormBackdropTone.deep.opacity(0.62), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.64),
                        .init(color: StormBackdropTone.deep.opacity(0.58), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Slow, two-lobe accent glow. It sits above the loop and adds light rather than
/// covering it, so the storm keeps its texture while the screen never goes flat
/// black between lightning beats.
private struct StormAuroraView: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [AppTheme.accent.opacity(0.26), AppTheme.accent.opacity(0.06), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: proxy.size.width * 1.05
                )
                .scaleEffect(drift ? 1.10 : 0.88, anchor: .topTrailing)
                .offset(x: drift ? -24 : 30, y: drift ? 18 : -20)

                RadialGradient(
                    colors: [AppTheme.accent.opacity(0.16), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.9
                )
                .scaleEffect(drift ? 0.92 : 1.08, anchor: .bottomLeading)
            }
            .blur(radius: 36)
            .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: drift)
            .onAppear { drift = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AppCinematicReveal: ViewModifier {
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode
    @State private var isVisible = false
    let delay: Double

    private var isInstant: Bool { reduceMotion || performanceMode }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || isInstant ? 1 : 0)
            .offset(y: !isVisible && !isInstant ? 14 : 0)
            .blur(radius: !isVisible && !isInstant ? 4 : 0)
            .onAppear {
                guard !isInstant else {
                    isVisible = true
                    return
                }
                withAnimation(.spring(response: 0.58, dampingFraction: 0.88).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func appCinematicReveal(delay: Double = 0) -> some View {
        modifier(AppCinematicReveal(delay: delay))
    }

    /// Parallax for a named layer. New code uses this; the scalar below is legacy.
    func appDepthLayer(_ layer: AppDepthLayer) -> some View {
        modifier(AppDepthMotion(travel: layer.travel, rotation: layer.rotation))
    }
}

@MainActor
final class DeviceTiltMotion: ObservableObject {
    @Published private(set) var pitch = 0.0
    @Published private(set) var roll = 0.0

    private let motionManager = CMMotionManager()
    private var isRunning = false

    func start() {
        guard !isRunning, motionManager.isDeviceMotionAvailable else { return }
        guard !AppPerformance.isConstrained else { return }
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard error == nil, let attitude = motion?.attitude else { return }
            let targetPitch = Self.normalized(attitude.pitch)
            let targetRoll = Self.normalized(attitude.roll)
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.pitch += (targetPitch - self.pitch) * 0.22
                self.roll += (targetRoll - self.roll) * 0.22
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        pitch = 0
        roll = 0
    }

    private nonisolated static func normalized(_ angle: Double) -> Double {
        min(max(angle / 0.78, -1), 1)
    }
}

/// The screen is a stack, not a plane. Each layer states how far it travels, so the
/// parallax is a property of the layout instead of a number someone guessed at the call
/// site. Backdrop moves most, type never moves: text that drifts is text that reads worse.
enum AppDepthLayer {
    case backdrop
    case hero
    case card
    case type

    /// Fraction of the capped travel, in points.
    var travel: CGFloat {
        switch self {
        case .backdrop: return 1.00
        case .hero: return 0.55
        case .card: return 0.30
        case .type: return 0
        }
    }

    /// Fraction of the capped rotation, in degrees. Type stays flat for legibility.
    var rotation: CGFloat {
        switch self {
        case .backdrop: return 0.25
        case .hero: return 1.00
        case .card: return 0.45
        case .type: return 0
        }
    }
}

enum AppDepthMetrics {
    /// Past roughly 8 pt of travel and 5 degrees of rotation the illusion stops reading
    /// as depth and starts reading as a wobble, so both are hard caps rather than hints.
    static let maxTravel: CGFloat = 8
    static let maxRotation: Double = 5
    static let perspective: CGFloat = 0.78
    /// Matches the 30 Hz motion update: fast enough to feel attached, slow enough not to
    /// chase the sensor's noise.
    static let follow: Double = 0.07
}

struct AppDepthMotion: ViewModifier {
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode

    let travel: CGFloat
    let rotation: CGFloat

    private var isStatic: Bool { reduceMotion || performanceMode }
    private var roll: CGFloat { isStatic ? 0 : CGFloat(deviceTilt.roll) }
    private var pitch: CGFloat { isStatic ? 0 : CGFloat(deviceTilt.pitch) }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(Double(pitch) * AppDepthMetrics.maxRotation * Double(rotation)),
                axis: (x: 1, y: 0, z: 0),
                perspective: AppDepthMetrics.perspective
            )
            .rotation3DEffect(
                .degrees(Double(roll) * AppDepthMetrics.maxRotation * Double(rotation)),
                axis: (x: 0, y: 1, z: 0),
                perspective: AppDepthMetrics.perspective
            )
            .offset(
                x: roll * AppDepthMetrics.maxTravel * travel,
                y: pitch * -AppDepthMetrics.maxTravel * 0.6 * travel
            )
            .animation(isStatic ? nil : .linear(duration: AppDepthMetrics.follow), value: deviceTilt.roll)
            .animation(isStatic ? nil : .linear(duration: AppDepthMetrics.follow), value: deviceTilt.pitch)
    }
}

enum AppHaptics {
    static func tap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.65)
    }

    static func select() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }
}

@MainActor
enum PatchAudioFeedback {
    private static var player: AVAudioPlayer?

    static func play(enabled: Bool) {
        let resource = enabled ? "PatchActivated" : "PatchDeactivated"
        guard let audioAsset = NSDataAsset(name: resource) else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? session.setActive(true)

        do {
            player?.stop()
            let nextPlayer = try AVAudioPlayer(data: audioAsset.data)
            nextPlayer.prepareToPlay()
            player = nextPlayer
            nextPlayer.play()
        } catch {
            player = nil
        }
    }
}

struct AppPressButtonStyle: ButtonStyle {
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion && !performanceMode ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.02 : 0)
            .animation(
                reduceMotion || performanceMode
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: frameSize, height: frameSize)
            .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "TryStoreTheme")
                ?? UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The real Free Fire MAX artwork already bundled for the player tools. It
/// stands in for the app glyph on screens that are about the game itself.
struct FreeFireLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Image("FreeFireMax")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.32), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// A quiet charcoal plinth. Surface tone and generous corners create separation;
/// decorative borders, material blur and shadows are intentionally absent.
struct AppPanelSurface: ViewModifier {
    var radius: CGFloat = AppRadius.panel
    var tint: Color = AppTheme.accent

    func body(content: Content) -> some View {
        content
            .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func appPanel(radius: CGFloat = AppRadius.panel, tint: Color = AppTheme.accent) -> some View {
        modifier(AppPanelSurface(radius: radius, tint: tint))
    }

    func appSpecularSheen(
        intensity: CGFloat = 1,
        cornerRadius: CGFloat = AppRadius.panel
    ) -> some View {
        modifier(AppSpecularSheen(intensity: intensity, cornerRadius: cornerRadius))
    }

    /// Tab and module switching answers the hand. No-op before iOS 17.
    @ViewBuilder
    func appSelectionFeedback<V: Equatable>(trigger: V) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }

    /// Discrete symbol bounce, a no-op before iOS 17.
    @ViewBuilder
    func appBounce<V: Equatable>(trigger: V) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }

    /// Haptic confirmation, a no-op before iOS 17.
    @ViewBuilder
    func appSuccessFeedback<V: Equatable>(trigger: V) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.success, trigger: trigger)
        } else {
            self
        }
    }
}

// MARK: - Section header

struct AppSectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppType.section())
                    .foregroundStyle(AppPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metric tile

struct AppMetricTile: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = AppTheme.accent
    var minHeight: CGFloat = 78

    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppType.label())
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(AppType.value())
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : AppMotion.tile, value: value)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .padding(AppSpacing.m)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
        )
    }
}

// MARK: - Ring gauge

/// Open 270° arc with the reading inside it, so the number never depends on
/// the arc alone to communicate the value.
struct AppRingGauge: View {
    let progress: Double
    let value: String
    let caption: String
    var tint: Color = AppTheme.accent
    var diameter: CGFloat = 116

    @Environment(\.appReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(AppPalette.hairline.opacity(0.80), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(AppType.label())
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, AppSpacing.m)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : AppMotion.tile, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }
}

// MARK: - Stat chip

struct AppStatChip: View {
    let icon: String
    let text: String
    var tint: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(AppType.label())
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.s)
        .background(AppPalette.raised, in: Capsule())
    }
}

// MARK: - Action button

struct AppActionButton: View {
    let title: String
    let icon: String
    var tint: Color = AppTheme.accent
    var isProminent: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(AppType.label().weight(isProminent ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: isProminent ? nil : .infinity, minHeight: 44)
            .background { background }
            .overlay { gloss }
            .overlay { border }
            .clipShape(Capsule())
            .shadow(
                color: isProminent && isEnabled ? tint.opacity(0.30) : .clear,
                radius: 12,
                y: 5
            )
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : AppMotion.tile, value: isEnabled)
    }

    private var foreground: Color {
        guard isEnabled else { return AppPalette.textTertiary }
        // The accent is bright enough that black reads at 8.5:1 on it; white sat near 2.4:1.
        return isProminent ? AppPalette.canvas : AppPalette.brand
    }

    /// The accent is a light source, not a fill: a short vertical ramp plus a
    /// top gloss reads as a physical key instead of a flat sticker.
    @ViewBuilder
    private var background: some View {
        if isProminent && isEnabled {
            Capsule().fill(
                LinearGradient(
                    colors: [tint, tint.opacity(0.80)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            Capsule().fill(tint.opacity(0.10))
        }
    }

    private var gloss: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isProminent && isEnabled ? 0.26 : 0.06),
                        Color.white.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .allowsHitTesting(false)
    }

    private var border: some View {
        Capsule()
            .strokeBorder(
                isProminent && isEnabled ? Color.white.opacity(0.30) : tint.opacity(0.45),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Small parts

struct AppHairline: View {
    var tint: Color = AppTheme.accent

    var body: some View {
        Rectangle()
            .fill(AppPalette.hairline.opacity(0.65))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct AppIconBadge: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Specular sheen

/// A wide, low-opacity highlight that leans with the device. Static cards read as
/// flat rectangles; a surface that catches light reads as a real one. Switched off
/// for Reduce Motion and Reduce Transparency, and it never intercepts a touch.
struct AppSpecularSheen: ViewModifier {
    var intensity: CGFloat = 1
    var cornerRadius: CGFloat = AppRadius.panel

    func body(content: Content) -> some View {
        content
    }
}

// MARK: - Skeleton

/// Placeholder rows for work that is running, so a list that is still filling
/// shows its own shape instead of a spinner floating in empty space.
struct AppSkeleton: View {
    var height: CGFloat = 56
    var radius: CGFloat = AppRadius.tile

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode
    @State private var sweep: CGFloat = -0.6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(AppPalette.raised.opacity(0.42))
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: proxy.size.width * sweep)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppPalette.hairline.opacity(0.55), lineWidth: 1)
            )
            .onAppear {
                guard !reduceMotion, !performanceMode else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    sweep = 1.4
                }
            }
            .accessibilityHidden(true)
    }
}

struct AppSkeletonList: View {
    var rows: Int = 4

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ForEach(0..<rows, id: \.self) { _ in
                AppSkeleton()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty state

/// One shape for every "nothing here yet": icon badge, headline, one line of
/// explanation. Keeps the empty screens from each inventing their own layout.
struct AppEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            AppIconBadge(systemName: icon, tint: tint, size: 46)
            Text(title)
                .font(AppType.label())
                .tracking(0.8)
                .foregroundStyle(AppPalette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - HUD chrome

/// The control deck's blue-black glass. Every tone is the logo blue laid over
/// the canvas, so the HUD stays inside the same palette as the rest of the app
/// instead of becoming a second theme.
enum AppHUD {
    static let deep = Color(red: 0.004, green: 0.020, blue: 0.043)
    static let panel = Color(red: 0.012, green: 0.047, blue: 0.094)
    static let panelLift = Color(red: 0.020, green: 0.086, blue: 0.157)
    static let tile = Color(red: 0.008, green: 0.035, blue: 0.071)
    static let strokeSoft = AppPalette.brand.opacity(0.26)
}

/// One silhouette for every HUD surface. Panels, tiles and the tab bar use cut
/// corners so the deck reads as machined chrome rather than rounded cards.
struct AppChamferShape: Shape {
    var cut: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let inset = min(cut, min(rect.width, rect.height) * 0.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        path.closeSubpath()
        return path
    }
}

/// Body callouts point at the anatomy they describe. The right edge is the
/// pointer, the left edge is cut, and the same shape is used for every chip.
struct AppPointerShape: Shape {
    var point: CGFloat = 15
    var cut: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let bevel = min(cut, rect.height * 0.5)
        let tip = min(point, rect.width * 0.35)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + bevel, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bevel, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bevel))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bevel))
        path.closeSubpath()
        return path
    }
}

/// The dock silhouette: cut top corners, square bottom so it can run into the
/// home-indicator area without a visible seam.
struct AppHUDTabBarShape: Shape {
    var cut: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let bevel = min(cut, min(rect.width, rect.height) * 0.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bevel))
        path.addLine(to: CGPoint(x: rect.minX + bevel, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bevel, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bevel))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A single heartbeat trace, used as the system panel's ornament.
struct AppHUDECGLine: Shape {
    func path(in rect: CGRect) -> Path {
        let mid = rect.midY
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.18, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.24, y: mid - height * 0.32))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.30, y: mid + height * 0.26))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.35, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.52, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.57, y: mid - height * 0.44))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.62, y: mid + height * 0.34))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.68, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
        return path
    }
}

private struct AppHUDPanelSurface: ViewModifier {
    var cut: CGFloat
    var tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = AppChamferShape(cut: cut)
        content
            .background {
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: AppHUD.panelLift.opacity(reduceTransparency ? 1 : 0.92), location: 0),
                                .init(color: AppHUD.panel.opacity(reduceTransparency ? 1 : 0.88), location: 0.55),
                                .init(color: AppHUD.deep, location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RadialGradient(
                            colors: [tint.opacity(0.14), .clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 320
                        )
                        .clipShape(shape)
                    }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.72),
                            tint.opacity(0.20),
                            tint.opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: tint.opacity(0.16), radius: 16, y: 6)
    }
}

extension View {
    /// Machined panel for the HUD deck. The radius scale does not apply here:
    /// the silhouette is cut, not rounded.
    func appHUDPanel(cut: CGFloat = 18, tint: Color = AppPalette.brand) -> some View {
        modifier(AppHUDPanelSurface(cut: cut, tint: tint))
    }
}

struct AppHUDIconButton: View {
    let icon: String
    let label: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppPalette.brand)
                .frame(width: 46, height: 46)
                .background {
                    AppChamferShape(cut: 13)
                        .fill(
                            LinearGradient(
                                colors: [AppHUD.panelLift, AppHUD.deep],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    AppChamferShape(cut: 13)
                        .stroke(AppPalette.brand.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: AppPalette.brand.opacity(0.25), radius: 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? icon)
    }
}

struct AppHUDCallout: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.5), AppPalette.brand.opacity(0.26), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 9
                        )
                    )
                Circle()
                    .strokeBorder(AppPalette.brand.opacity(0.55), lineWidth: 0.8)
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppPalette.textPrimary)
            }
            .frame(width: 18, height: 18)
            .shadow(color: AppPalette.brand.opacity(0.8), radius: 4)
            Text(title)
                .font(AppType.hudCallout())
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(AppPalette.brand.opacity(0.85))
        }
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .frame(minHeight: 44)
        .background {
            AppPointerShape()
                .fill(
                    LinearGradient(
                        colors: [AppHUD.panelLift.opacity(0.98), AppHUD.deep.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            AppPointerShape()
                .stroke(AppPalette.brand.opacity(0.60), lineWidth: 1)
        }
        .shadow(color: AppPalette.brand.opacity(0.25), radius: 8)
    }
}

struct AppHUDTabItem: Identifiable {
    let id: Int
    let icon: String
    let title: String
}

struct AppHUDTabBar: View {
    @Binding var selection: Int
    let items: [AppHUDTabItem]

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    guard selection != item.id else { return }
                    AppHaptics.select()
                    withAnimation(reduceMotion ? nil : AppMotion.surface) {
                        selection = item.id
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title)
                            .font(AppType.hudTab())
                            .tracking(0.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .foregroundStyle(selection == item.id ? AppPalette.brand : AppPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background {
                        if selection == item.id {
                            AppChamferShape(cut: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppPalette.brand.opacity(0.24),
                                            AppPalette.brand.opacity(0.04)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                    .overlay {
                        if selection == item.id {
                            AppChamferShape(cut: 12)
                                .stroke(AppPalette.brand.opacity(0.52), lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AppPressButtonStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(
                    selection == item.id ? AccessibilityTraits.isSelected : AccessibilityTraits()
                )
            }
        }
        .padding(6)
        .background {
            AppHUDTabBarShape()
                .fill(
                    LinearGradient(
                        colors: reduceTransparency
                            ? [AppHUD.panel, AppHUD.deep]
                            : [AppHUD.panel.opacity(0.98), AppHUD.deep.opacity(0.99)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, AppPalette.brand.opacity(0.65), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
                .overlay {
                    AppHUDTabBarShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppPalette.brand.opacity(0.55),
                                    AppPalette.brand.opacity(0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: AppPalette.brand.opacity(0.22), radius: 18, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

/// Cyan shard debris and short electrical arcs inspired by the effect plates.
/// Vector-only, so it scales on every phone; Reduce Motion and the lean
/// performance path drop it to a single static frame.
struct HUDShardField: View {
    var isActive: Bool = true
    var intensity: Double = 1
    var showsCore: Bool = true

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode

    private var isPaused: Bool { !isActive || reduceMotion || performanceMode }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let time = isPaused ? 2.4 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, size: size, time: time)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = size.width
        let height = size.height
        guard width > 20, height > 20 else { return }
        let center = CGPoint(x: width * 0.5, y: height * 0.48)
        let base = min(width, height)
        let t = time

        if showsCore {
            var glow = context
            glow.addFilter(.blur(radius: base * 0.12))
            let rect = CGRect(
                x: center.x - base * 0.38,
                y: center.y - base * 0.30,
                width: base * 0.76,
                height: base * 0.60
            )
            glow.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        AppPalette.brand.opacity(0.34 * intensity),
                        AppPalette.brand.opacity(0.05 * intensity),
                        .clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: base * 0.42
                )
            )
        }

        for index in 0..<30 {
            let phase = Double(index) * 0.37
            let wobble = CGFloat(sin(t * 0.55 + phase))
            let angle = (Double(index) / 30.0) * .pi * 2 + phase * 0.11
            let radius = base * CGFloat(0.26 + 0.10 * (0.5 + 0.5 * sin(phase * 2.1))) + wobble * base * 0.018
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius * 1.22,
                y: center.y + CGFloat(sin(angle)) * radius * 0.78
            )
            let shardSize = base * CGFloat(index % 7 == 0 ? 0.052 : 0.026)
                * CGFloat(0.8 + 0.35 * (0.5 + 0.5 * sin(t * 0.8 + phase)))
            let rotation = angle * 1.7 + t * 0.12 + phase
            let path = triangle(at: point, radius: shardSize, rotation: rotation)
            let hot = index % 6 == 0
            let alpha = (hot ? 0.50 : 0.20) * intensity
                * (0.72 + 0.28 * (0.5 + 0.5 * sin(t * 1.4 + phase)))

            context.fill(
                path,
                with: .color(hot ? AppPalette.textPrimary.opacity(alpha) : AppPalette.brand.opacity(alpha))
            )
            context.stroke(
                path,
                with: .color(AppPalette.brand.opacity(min(0.8, alpha + 0.18))),
                lineWidth: 0.7
            )
        }

        for index in 0..<3 {
            let seed = Double(index) * 1.9
            var path = Path()
            let start = CGPoint(x: width * (0.18 + 0.10 * CGFloat(index)), y: height * 0.16)
            path.move(to: start)
            var point = start
            for step in 1...5 {
                let fraction = CGFloat(step) / 5
                point = CGPoint(
                    x: start.x + width * 0.16 * fraction + CGFloat(sin(t * 1.7 + seed + Double(step))) * 10,
                    y: start.y + height * 0.14 * fraction
                )
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(AppPalette.brand.opacity(0.20 * intensity)),
                lineWidth: 0.9
            )
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x + 22, y: point.y + 18))
            path.addLine(to: CGPoint(x: point.x + 12, y: point.y + 36))
            context.stroke(
                path,
                with: .color(AppPalette.textPrimary.opacity(0.10 * intensity)),
                lineWidth: 0.7
            )
        }
    }

    private func triangle(at point: CGPoint, radius: CGFloat, rotation: Double) -> Path {
        var path = Path()
        for index in 0..<3 {
            let angle = rotation + Double(index) * (2 * .pi / 3)
            let vertex = CGPoint(
                x: point.x + CGFloat(cos(angle)) * radius,
                y: point.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: vertex)
            } else {
                path.addLine(to: vertex)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - HUD console chrome

/// A static machined grid with corner brackets. It gives the Intel and Cleaner
/// consoles the same drawn-in-the-dark deck as Home without adding another
/// animation loop; the moving layer is the shared shard field underneath.
struct HUDGridField: View {
    var intensity: Double = 1

    var body: some View {
        Canvas { context, size in
            guard size.width > 40, size.height > 40 else { return }
            let spacing: CGFloat = 34
            var grid = Path()

            var x = spacing
            while x < size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y = spacing
            while y < size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(
                grid,
                with: .color(AppPalette.brand.opacity(0.10 * intensity)),
                lineWidth: 0.6
            )

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: size.height * 0.34))
            horizon.addLine(to: CGPoint(x: size.width, y: size.height * 0.34))
            context.stroke(
                horizon,
                with: .color(AppPalette.brand.opacity(0.18 * intensity)),
                lineWidth: 0.8
            )

            let inset: CGFloat = 12
            let arm: CGFloat = 18
            var brackets = Path()
            brackets.move(to: CGPoint(x: inset, y: inset + arm))
            brackets.addLine(to: CGPoint(x: inset, y: inset))
            brackets.addLine(to: CGPoint(x: inset + arm, y: inset))
            brackets.move(to: CGPoint(x: size.width - inset - arm, y: inset))
            brackets.addLine(to: CGPoint(x: size.width - inset, y: inset))
            brackets.addLine(to: CGPoint(x: size.width - inset, y: inset + arm))
            brackets.move(to: CGPoint(x: inset, y: size.height - inset - arm))
            brackets.addLine(to: CGPoint(x: inset, y: size.height - inset))
            brackets.addLine(to: CGPoint(x: inset + arm, y: size.height - inset))
            brackets.move(to: CGPoint(x: size.width - inset - arm, y: size.height - inset))
            brackets.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            brackets.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - arm))
            context.stroke(
                brackets,
                with: .color(AppPalette.brand.opacity(0.42 * intensity)),
                lineWidth: 1
            )

            var ticks = Path()
            let tickY = size.height * 0.34
            for index in 0..<7 {
                let tickX = size.width * 0.5 + CGFloat(index - 3) * 16
                ticks.move(to: CGPoint(x: tickX, y: tickY - 3))
                ticks.addLine(to: CGPoint(x: tickX, y: tickY + 3))
            }
            context.stroke(
                ticks,
                with: .color(AppPalette.brand.opacity(0.34 * intensity)),
                lineWidth: 1
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(
            RadialGradient(
                colors: [.black, .black.opacity(0.72), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 560
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Grid, shard debris and a quiet top/bottom scrim for the secondary consoles.
/// Everything is decorative and non-interactive; Reduce Motion and the lean
/// performance path stop the shards through `HUDShardField`.
struct HUDConsoleBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        ZStack {
            HUDGridField(intensity: intensity)

            HUDShardField(isActive: true, intensity: 0.45 * intensity, showsCore: false)
                .opacity(0.55)

            LinearGradient(
                colors: [
                    AppHUD.deep.opacity(0.30),
                    .clear,
                    AppHUD.deep.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Numbered console section heading: cut index block, compact HUD title, LED
/// rule and a symbol badge. Callers pass localized strings; the index is the
/// only literal, so the console reads as one ordered deck.
struct HUDSectionHeader: View {
    let index: String
    let icon: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.s) {
                Text(index)
                    .font(AppType.hudKicker().weight(.black))
                    .foregroundStyle(AppPalette.canvas)
                    .frame(width: 26, height: 26)
                    .background(AppPalette.brand, in: AppChamferShape(cut: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppType.hudStageTitle())
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppType.hudKicker())
                            .tracking(0.6)
                            .foregroundStyle(AppPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: AppSpacing.s)

                if let trailing {
                    Text(trailing)
                        .font(AppType.hudKicker())
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.brand)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(AppPalette.brand.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(AppPalette.brand.opacity(0.32), lineWidth: 0.8))
                }

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 26, height: 26)
                    .background(AppPalette.brand.opacity(0.08), in: AppChamferShape(cut: 7))
                    .overlay(AppChamferShape(cut: 7).stroke(AppPalette.brand.opacity(0.24), lineWidth: 0.8))
            }

            HStack(spacing: 3) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.brand.opacity(0.52), AppPalette.brand.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Rectangle()
                    .fill(AppPalette.brand.opacity(0.72))
                    .frame(width: 4, height: 4)
                    .rotationEffect(.degrees(45))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.brand.opacity(0.05), AppPalette.brand.opacity(0.52)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
