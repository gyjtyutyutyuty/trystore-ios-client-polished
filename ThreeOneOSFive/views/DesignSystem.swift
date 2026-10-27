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
        .system(size: compact ? 30 : 38, weight: .black, design: .rounded)
    }
    static func display() -> Font { .system(size: 22, weight: .black, design: .rounded) }
    static func section() -> Font { .system(size: 13, weight: .black, design: .rounded) }
    static func label() -> Font { .system(size: 11, weight: .black, design: .rounded) }
    static func body() -> Font { .system(size: 13, weight: .semibold, design: .rounded) }
    static func value() -> Font { .system(size: 15, weight: .bold, design: .rounded) }
    static func meta() -> Font { .system(size: 11, weight: .medium, design: .rounded) }
    static func digits(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
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

    func appGyroTilt(intensity: CGFloat = 1) -> some View {
        modifier(AppGyroTilt(intensity: intensity))
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

struct AppGyroTilt: ViewModifier {
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @Environment(\.appReduceMotion) private var reduceMotion
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : deviceTilt.pitch * 2.8 * Double(intensity)),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.78
            )
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : deviceTilt.roll * 3.6 * Double(intensity)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.78
            )
            .offset(
                x: reduceMotion ? 0 : CGFloat(deviceTilt.roll) * 3.5 * intensity,
                y: reduceMotion ? 0 : CGFloat(deviceTilt.pitch) * -2.5 * intensity
            )
            .animation(reduceMotion ? nil : .linear(duration: 0.07), value: deviceTilt.roll)
            .animation(reduceMotion ? nil : .linear(duration: 0.07), value: deviceTilt.pitch)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .shadow(color: AppTheme.accent.opacity(configuration.isPressed ? 0.16 : 0), radius: 12, y: 3)
            .animation(.spring(response: 0.28, dampingFraction: 0.66), value: configuration.isPressed)
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
        .appGyroTilt(intensity: 0.38)
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
