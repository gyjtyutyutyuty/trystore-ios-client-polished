import SwiftUI
import UIKit
import AVFoundation
import CoreMotion
import Combine

enum AppTheme {
    static let accent = Color(red: 0.78, green: 0.86, blue: 0.98)
    static let pageBackground = Color(red: 0.025, green: 0.032, blue: 0.048)
    static let consoleBackground = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let referenceCard = Color(red: 0.085, green: 0.102, blue: 0.132)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @State private var lightsDrift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.075, green: 0.083, blue: 0.13), AppTheme.pageBackground, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
