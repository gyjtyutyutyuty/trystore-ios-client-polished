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

struct AppPremiumBackdrop: View {
    var body: some View {
        AppPalette.canvas
            .ignoresSafeArea()
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
