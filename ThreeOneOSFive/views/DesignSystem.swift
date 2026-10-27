import SwiftUI
import UIKit
import AVFoundation
import CoreMotion
import Combine

/// Base surface colours. Layered from canvas (deepest) through surface to
/// raised so panels separate by tone as well as by edge, per the Dark Mode
/// guidance to preserve depth cues instead of inverting a light theme.
/// Contrast of body text on the canvas is kept above 4.5:1.
enum AppPalette {
    static let canvas = Color(red: 0.043, green: 0.059, blue: 0.078)
    static let surface = Color(red: 0.067, green: 0.094, blue: 0.129)
    static let raised = Color(red: 0.098, green: 0.137, blue: 0.176)
    static let hairline = Color(red: 0.161, green: 0.208, blue: 0.259)

    static let textPrimary = Color(red: 0.949, green: 0.961, blue: 0.969)
    static let textSecondary = Color(red: 0.655, green: 0.698, blue: 0.749)
    static let textTertiary = Color(red: 0.561, green: 0.608, blue: 0.659)

    /// Primary accent. Reads at roughly 10:1 on the canvas, so the same colour
    /// works for text, icons and fills without a separate on-accent tone.
    static let mint = Color(red: 0.396, green: 0.839, blue: 0.760)
    /// Secondary data colour, used only when two series must be told apart.
    static let blue = Color(red: 0.545, green: 0.659, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.776, blue: 0.427)
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
}

enum AppRadius {
    static let chip: CGFloat = 10
    static let control: CGFloat = 14
    static let tile: CGFloat = 18
    static let panel: CGFloat = 22
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

/// Type scale. Nothing in the interface goes below 11 pt, which is the
/// smallest size the typography guidance treats as comfortably legible.
enum AppType {
    static func hero(_ compact: Bool) -> Font {
        scaled(compact ? 30 : 38, weight: .black, textStyle: .largeTitle)
    }
    static func display() -> Font { scaled(22, weight: .black, textStyle: .title2) }
    static func section() -> Font { scaled(13, weight: .black, textStyle: .headline) }
    static func label() -> Font { scaled(11, weight: .black, textStyle: .caption1) }
    static func body() -> Font { scaled(13, weight: .semibold, textStyle: .body) }
    static func value() -> Font { scaled(15, weight: .bold, textStyle: .body) }
    static func meta() -> Font { scaled(11, weight: .medium, textStyle: .footnote) }

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
        return Font(dynamic.withDescriptor(roundedDescriptor))
    }
}

enum AppTheme {
    static let accent = AppPalette.mint
    static let accentSecondary = AppPalette.blue
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

struct AppPremiumBackdrop: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @State private var lightsDrift = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.075, green: 0.083, blue: 0.13), AppTheme.pageBackground, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if #available(iOS 18.0, *), !reduceTransparency {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5], [lightsDrift ? 0.62 : 0.38, lightsDrift ? 0.44 : 0.56], [1.0, 0.5],
                            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                        ],
                        colors: [
                            AppPalette.canvas, AppPalette.surface, AppPalette.canvas,
                            AppPalette.surface, Color(red: 0.36, green: 0.30, blue: 0.72).opacity(0.55), AppPalette.raised,
                            AppPalette.canvas, AppPalette.raised, AppPalette.canvas
                        ]
                    )
                    .opacity(0.72)
                    .blendMode(.plusLighter)
                }
                Circle()
                    .fill(Color(red: 0.34, green: 0.28, blue: 0.95).opacity(0.15))
                    .frame(width: min(proxy.size.width * 0.90, 390))
                    .blur(radius: 100)
                    .offset(
                        x: proxy.size.width * (lightsDrift ? 0.42 : 0.30) + CGFloat(deviceTilt.roll) * 18,
                        y: -proxy.size.height * (lightsDrift ? 0.34 : 0.42) - CGFloat(deviceTilt.pitch) * 16
                    )
                Circle()
                    .fill(Color(red: 0.12, green: 0.78, blue: 0.76).opacity(0.10))
                    .frame(width: min(proxy.size.width * 0.72, 310))
                    .blur(radius: 94)
                    .offset(
                        x: proxy.size.width * (lightsDrift ? -0.42 : -0.30) + CGFloat(deviceTilt.roll) * 12,
                        y: proxy.size.height * (lightsDrift ? 0.36 : 0.46) - CGFloat(deviceTilt.pitch) * 11
                    )
                Circle()
                    .fill(Color(red: 0.94, green: 0.34, blue: 0.60).opacity(0.075))
                    .frame(width: min(proxy.size.width * 0.56, 240))
                    .blur(radius: 88)
                    .offset(
                        x: proxy.size.width * (lightsDrift ? 0.18 : -0.05),
                        y: proxy.size.height * (lightsDrift ? 0.10 : -0.04)
                    )
                LinearGradient(
                    colors: [.clear, Color.cyan.opacity(0.025), Color.white.opacity(0.035), Color.purple.opacity(0.025), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: proxy.size.width * 0.9)
                .rotationEffect(.degrees(-18))
                .offset(x: proxy.size.width * (lightsDrift ? 1.1 : -1.1) + CGFloat(deviceTilt.roll) * 14)
                .blur(radius: 18)
                .blendMode(.screen)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                lightsDrift = true
            }
        }
    }
}

struct AppCinematicReveal: ViewModifier {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: !isVisible && !reduceMotion ? 14 : 0)
            .blur(radius: !isVisible && !reduceMotion ? 4 : 0)
            .onAppear {
                guard !reduceMotion else {
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

    let travel: CGFloat
    let rotation: CGFloat

    private var roll: CGFloat { reduceMotion ? 0 : CGFloat(deviceTilt.roll) }
    private var pitch: CGFloat { reduceMotion ? 0 : CGFloat(deviceTilt.pitch) }

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
            .animation(reduceMotion ? nil : .linear(duration: AppDepthMetrics.follow), value: deviceTilt.roll)
            .animation(reduceMotion ? nil : .linear(duration: AppDepthMetrics.follow), value: deviceTilt.pitch)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // A card that is pushed compresses slightly and its shadow tightens: the
            // surface moves down, it does not shrink away from the finger.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .brightness(configuration.isPressed ? 0.02 : 0)
            .shadow(
                color: AppTheme.accent.opacity(configuration.isPressed ? 0.10 : 0),
                radius: configuration.isPressed ? 7 : 12,
                y: configuration.isPressed ? 1 : 3
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.28), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tint.opacity(0.22), lineWidth: 1))
        .shadow(color: tint.opacity(0.12), radius: 8, y: 3)
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
        .appDepthLayer(.card)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// Shared panel chrome: frosted material over the ambient backdrop, a hairline
/// edge that catches the light at the top-left corner, and an opaque fill
/// whenever Reduce Transparency is on so text never sits on an unpredictable blur.
struct AppPanelSurface: ViewModifier {
    var radius: CGFloat = AppRadius.panel
    var tint: Color = AppTheme.accent

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background { fill }
            .overlay { edge }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder
    private var fill: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppPalette.raised)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppPalette.surface.opacity(0.52), AppPalette.canvas.opacity(0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }

    private var edge: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.20), tint.opacity(0.22), AppPalette.hairline.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
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
        HStack(spacing: AppSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppType.section())
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppType.label())
                        .tracking(0.5)
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
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppType.label())
                    .tracking(0.7)
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
        .appPanel(radius: AppRadius.tile, tint: tint)
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
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.45), tint, tint.opacity(0.80)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.45), radius: 12)

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 21, weight: .black, design: .rounded))
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
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint)
            Text(text)
                .font(AppType.label())
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.s)
        .background(AppPalette.raised.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
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
                    .font(.system(size: 13, weight: .black))
                Text(title)
                    .font(AppType.label())
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background { background }
            .overlay { border }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .shadow(color: isProminent && isEnabled ? tint.opacity(0.34) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : AppMotion.tile, value: isEnabled)
    }

    private var foreground: Color {
        guard isEnabled else { return AppPalette.textTertiary }
        return isProminent ? Color(red: 0.02, green: 0.07, blue: 0.07) : AppPalette.textPrimary
    }

    @ViewBuilder
    private var background: some View {
        if isProminent && isEnabled {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(AppPalette.raised.opacity(0.72))
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            .strokeBorder(
                isProminent && isEnabled ? Color.white.opacity(0.28) : tint.opacity(0.24),
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
            .fill(
                LinearGradient(
                    colors: [.clear, tint.opacity(0.38), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct AppIconBadge: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.30), tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.18), radius: 10, y: 4)
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

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion && !reduceTransparency {
                GeometryReader { proxy in
                    let lean = min(max(CGFloat((deviceTilt.roll + deviceTilt.pitch) / 2), -1), 1)
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.055 * Double(intensity)),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: proxy.size.width * 1.8, height: proxy.size.height * 2.6)
                    .rotationEffect(.degrees(-14))
                    .offset(
                        x: proxy.size.width * (0.30 + lean * 0.40),
                        y: -proxy.size.height * 0.62
                    )
                    .blendMode(.plusLighter)
                    .animation(reduceMotion ? nil : .linear(duration: 0.20), value: deviceTilt.roll)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Skeleton

/// Placeholder rows for work that is running, so a list that is still filling
/// shows its own shape instead of a spinner floating in empty space.
struct AppSkeleton: View {
    var height: CGFloat = 56
    var radius: CGFloat = AppRadius.tile

    @Environment(\.appReduceMotion) private var reduceMotion
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
                guard !reduceMotion else { return }
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
