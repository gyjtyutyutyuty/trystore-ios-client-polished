import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @State private var navigationState = AppTabNavigationState()

    private var selectedTab: Binding<Int> {
        Binding(
            get: { navigationState.selectedTab },
            set: { navigationState.select($0) }
        )
    }

    private var filesTabs: Binding<FilesTabSession> {
        Binding(
            get: { navigationState.filesTabs },
            set: { navigationState.setFilesTabs($0) }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            DashboardView(selectedTab: selectedTab)
                .tabItem { Label(language.text("tab.home"), systemImage: "house.fill") }
                .tag(AppSection.home.rawValue)

            AppDataBrowserView(tabSession: filesTabs)
                .tabItem { Label(language.text("tab.files"), systemImage: "folder.fill") }
                .tag(AppSection.files.rawValue)

            PatchProjectsView()
                .tabItem { Label(language.text("tab.patches"), systemImage: "square.stack.3d.up.fill") }
                .tag(AppSection.patches.rawValue)

            CleanerView()
                .tabItem { Label(language.text("tab.cleaner"), systemImage: "sparkles") }
                .tag(AppSection.cleaner.rawValue)

            if WallpaperFeatureSupportPolicy.isSupported(major: AppInfo.versionTuple.major) {
                WallpaperLabView()
                    .tabItem { Label(language.text("tab.wallpapers"), systemImage: "photo.on.rectangle.angled") }
                    .tag(AppSection.wallpapers.rawValue)
            }
        }
            .tint(PlatinumPalette.neonBlue)
            .imageScale(.small)
            .preferredColorScheme(.dark)
    }
}

// MARK: - DashboardView
private enum DashboardPatchTab: String, CaseIterable, Identifiable {
    case loadout
    case visuals

    var id: String { rawValue }
    var title: String { self == .loadout ? "Loadout" : "Visuals" }
    var icon: String { self == .loadout ? "scope" : "sparkles" }
}

private enum PlatinumPalette {
    static let bright = AppTheme.accent
    static let silver = AppTheme.electricBlue
    static let neonBlue = AppTheme.electricBlue
    static let graphite = Color(red: 0.055, green: 0.075, blue: 0.11)
    static let gunmetal = Color(red: 0.12, green: 0.15, blue: 0.20)
}

private struct PlatinumPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.055 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

private struct DashboardGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(LinearGradient(
                            colors: [Color.white.opacity(0.13), tint.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    }
            }
            .overlay {
                shape.stroke(LinearGradient(
                    colors: [tint.opacity(0.72), Color.white.opacity(0.34), Color.white.opacity(0.07), tint.opacity(0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
            }
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, tint.opacity(0.10), Color.white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: max(42, proxy.size.width * 0.22), height: proxy.size.height * 1.8)
                    .rotationEffect(.degrees(18))
                    .offset(x: sweep ? proxy.size.width + 110 : -130)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .shadow(color: tint.opacity(0.10), radius: 17, y: 7)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.45).delay(0.18)) {
                    sweep = true
                }
            }
    }
}

private struct DashboardTextMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isNeon = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isNeon || reduceMotion ? PlatinumPalette.neonBlue : PlatinumPalette.bright)
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? (isNeon || reduceMotion ? 1.012 : 0.995) : 0.97, anchor: .leading)
            .offset(y: isVisible || reduceMotion ? (isNeon || reduceMotion ? -0.8 : 0.8) : 4)
            .shadow(color: PlatinumPalette.neonBlue.opacity(isNeon && !reduceMotion ? 0.42 : 0), radius: isNeon ? 5 : 0)
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    isNeon = true
                    return
                }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.74).delay(delay)) {
                    isVisible = true
                }
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(delay)) {
                    isNeon = true
                }
            }
    }
}

private struct StaggeredDashboardTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isNeon = false
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .foregroundStyle(isNeon || reduceMotion ? PlatinumPalette.neonBlue : color)
                    .opacity(isVisible || reduceMotion ? 1 : 0)
                    .scaleEffect(isVisible || reduceMotion ? (isNeon || reduceMotion ? 1.02 : 0.995) : 0.94)
                    .offset(y: isVisible || reduceMotion ? (isNeon || reduceMotion ? -1.2 : 1.2) : 5)
                    .shadow(color: PlatinumPalette.neonBlue.opacity(isVisible && isNeon && !reduceMotion ? 0.34 : 0), radius: isNeon ? 4 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72).delay(Double(index) * 0.10),
                        value: isVisible
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.44).delay(Double(index) * 0.14),
                        value: isNeon
                    )
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            guard !reduceMotion else {
                isVisible = true
                isNeon = true
                return
            }
            isVisible = true
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isNeon = true
            }
        }
    }
}

private extension View {
    func dashboardGlass(cornerRadius: CGFloat, tint: Color = AppTheme.accent) -> some View {
        modifier(DashboardGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    func dashboardTextMotion(delay: Double = 0) -> some View {
        modifier(DashboardTextMotion(delay: delay))
    }
}

private struct PlatinumExpiryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let expirationDate: Date?
    let isActive: Bool

    @State private var sweep = false
    @State private var ringRotation = 0.0

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Circle()
                    .trim(from: 0.04, to: 0.76)
                    .stroke(
                        AngularGradient(
                            colors: [PlatinumPalette.bright.opacity(0.18), .white, PlatinumPalette.silver.opacity(0.28)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(ringRotation))
                Image(systemName: expirationDate == nil ? "key.fill" : "hourglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PlatinumPalette.bright)
            }
            .frame(width: 39, height: 39)
            .shadow(color: PlatinumPalette.silver.opacity(0.32), radius: 9)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LICENSE WINDOW")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PlatinumPalette.bright)
                        .dashboardTextMotion(delay: 0.05)
                    Spacer(minLength: 4)
                    Text(isActive ? "Authorized" : "Checking")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isActive ? PlatinumPalette.graphite : .white.opacity(0.76))
                        .dashboardTextMotion(delay: 0.09)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(isActive ? PlatinumPalette.bright : Color.white.opacity(0.12), in: Capsule())
                }

                if let expirationDate {
                    Text(expiryStamp(expirationDate))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                        .dashboardTextMotion(delay: 0.13)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(countdown(to: expirationDate, now: context.date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(PlatinumPalette.silver)
                            .monospacedDigit()
                            .dashboardTextMotion(delay: 0.18)
                    }
                } else {
                    Text("No expiry date")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PlatinumPalette.bright)
                        .dashboardTextMotion(delay: 0.13)
                    Text("The license service did not return an expiry date.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.58))
                        .dashboardTextMotion(delay: 0.18)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.13), Color.white.opacity(0.035), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [PlatinumPalette.bright.opacity(0.86), PlatinumPalette.silver.opacity(0.12), .white.opacity(0.48), PlatinumPalette.silver.opacity(0.14)],
                        center: .center,
                        startAngle: .degrees(ringRotation),
                        endAngle: .degrees(ringRotation + 360)
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 54)
                .rotationEffect(.degrees(18))
                .offset(x: sweep ? proxy.size.width + 70 : -70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
        }
        .shadow(color: PlatinumPalette.silver.opacity(0.12), radius: 13, y: 5)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 4.4).repeatForever(autoreverses: false)) {
                sweep = true
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    private func expiryStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func countdown(to expiry: Date, now: Date) -> String {
        let remaining = Int(expiry.timeIntervalSince(now))
        guard remaining > 0 else { return "EXPIRED" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        return String(format: "%02dd  %02dh  %02dm  %02ds left", days, hours, minutes, seconds)
    }
}

private struct DashboardPatchOption: Identifiable {
    let projectName: String
    let title: String
    let icon: String
    let color: Color
    let group: PatchToggleGroup?

    var id: String { projectName }

    static let loadout = [
        DashboardPatchOption(projectName: "HEAD", title: "HEAD", icon: "viewfinder", color: AppTheme.electricBlue, group: .aim),
        DashboardPatchOption(projectName: "NECK", title: "NECK", icon: "scope", color: AppTheme.accent, group: .aim),
        DashboardPatchOption(projectName: "HS PESSCOSO", title: "DRAG", icon: "arrow.up.right.and.arrow.down.left", color: AppTheme.electricBlue, group: .aim),
        DashboardPatchOption(projectName: "HS SLA PECHO", title: "PECHO", icon: "scope", color: AppTheme.accent, group: .aim)
    ]

    static let visuals = [
        DashboardPatchOption(projectName: "HOLOGRAMA ARMAS", title: "HOLOGRAMA ARMAS", icon: "sparkles", color: AppTheme.electricBlue, group: nil),
        DashboardPatchOption(projectName: "HOLOGRAMA PERSONAJE", title: "HOLOGRAMA PERSONAJE", icon: "person.crop.circle.badge.sparkles", color: AppTheme.accent, group: nil)
    ]

    static var all: [DashboardPatchOption] { loadout + visuals }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: Int
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var patchStore = PatchProjectStore(game: .max)
    @Namespace private var patchTabNamespace
    @State private var selectedPatchTab: DashboardPatchTab = .loadout
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var heroRingRotation = 0.0
    @State private var heroScan = false
    @State private var heroFloat = false
    @State private var previewFloat = false
    @State private var ambientTouchPoint = CGPoint(x: 180, y: 260)
    @State private var ambientTouchStrength = 0.0
    @State private var ambientPulseID = 0
    @State private var patchSheen = false

    var body: some View {
        NavigationStack {
            ZStack {
                TryStoreAmbientBackground(
                    touchPoint: ambientTouchPoint,
                    touchStrength: ambientTouchStrength
                )
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        topBar
                            .appCinematicReveal(delay: 0.02)
                            .appGyroTilt(intensity: 0.08)
                        heroPanel
                            .appCinematicReveal(delay: 0.07)
                            .appGyroTilt(intensity: 0.28)
                        characterCompatibilityPanel
                            .appCinematicReveal(delay: 0.10)
                            .appGyroTilt(intensity: 0.08)
                        telemetryStrip
                            .appCinematicReveal(delay: 0.19)
                            .appGyroTilt(intensity: 0.08)
                        deviceSection
                            .appCinematicReveal(delay: 0.25)
                            .appGyroTilt(intensity: 0.10)
                        quickStartPanel
                            .appCinematicReveal(delay: 0.31)
                            .appGyroTilt(intensity: 0.08)
                        characterPreviewPanel
                            .appCinematicReveal(delay: 0.37)
                            .appGyroTilt(intensity: 0.14)
                        socialLinksPanel
                            .appCinematicReveal(delay: 0.43)
                            .appGyroTilt(intensity: 0.08)
                        footerBar.appCinematicReveal(delay: 0.49)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .coordinateSpace(name: "dashboard-touch-surface")
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("dashboard-touch-surface"))
                    .onChanged { value in
                        registerAmbientTouch(at: value.location)
                    }
            )
            .background(AppTheme.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(PlatinumPalette.neonBlue)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
            .alert(item: $patchStore.alert) { alert in
                Alert(
                    title: Text(language.text(alert.titleKey)),
                    message: Text(alert.message(language: language)),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .tint(PlatinumPalette.neonBlue)
        .preferredColorScheme(.dark)
        .task {
            if let key = licenseManager.patchBundleKey {
                patchStore.installBundledResources(bundleKey: key)
            }
        }
        .task(id: ambientPulseID) {
            guard ambientPulseID > 0 else { return }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.2)) {
                ambientTouchStrength = 0
            }
        }
    }

    private func registerAmbientTouch(at point: CGPoint) {
        if UIAccessibility.isReduceMotionEnabled {
            ambientTouchPoint = point
            ambientTouchStrength = 1
        } else {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                ambientTouchPoint = point
                ambientTouchStrength = 1
            }
        }
        ambientPulseID &+= 1
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AppLogo(size: horizontalSizeClass == .compact ? 36 : 42)
                .padding(horizontalSizeClass == .compact ? 3 : 4)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.accent.opacity(0.22), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("TryStore")
                    .font(.system(size: horizontalSizeClass == .compact ? 19 : 21, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .dashboardTextMotion(delay: 0.04)
                Text("Free Fire MAX · Patch workspace")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.58))
                    .dashboardTextMotion(delay: 0.08)
            }
            Spacer(minLength: 4)
            if horizontalSizeClass == .regular {
                statusPill
            } else {
                Circle()
                    .fill(appState.isSupported ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(8)
                    .background(Color.black.opacity(0.38), in: Capsule())
                    .accessibilityLabel(appState.isSupported ? "Device status ready" : "Device compatibility review required")
            }
            headerButton(symbol: "apple.terminal", label: language.text("accessibility.open_logs")) {
                showLogs = true
            }
            headerButton(symbol: "slider.horizontal.3", label: language.text("accessibility.open_settings")) {
                showSettings = true
            }
        }
        .padding(.bottom, 2)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isSupported ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: appState.isSupported ? .green : .orange, radius: 5)
            Text(appState.isSupported ? "Ready" : "Review")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appState.isSupported ? .green : .orange)
                .dashboardTextMotion(delay: 0.1)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(LinearGradient(colors: [Color.white.opacity(0.45), (appState.isSupported ? Color.green : Color.orange).opacity(0.36)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .accessibilityLabel(appState.isSupported ? "Device status ready" : "Device compatibility review required")
    }

    private func headerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        let buttonSize: CGFloat = horizontalSizeClass == .compact ? 36 : 40
        Button {
            AppHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: buttonSize, height: buttonSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(LinearGradient(colors: [Color.cyan.opacity(0.42), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(label)
    }

    private var heroPanel: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.13, green: 0.16, blue: 0.21), Color(red: 0.06, green: 0.08, blue: 0.12), AppTheme.pageBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [PlatinumPalette.neonBlue.opacity(0.08), PlatinumPalette.neonBlue.opacity(0.9), Color.cyan.opacity(0.65), .white.opacity(0.12), PlatinumPalette.neonBlue.opacity(0.08)],
                .frame(width: 210, height: 210)
                            .appCinematicReveal(delay: 0.13)
                .offset(x: 25, y: 26)
            Circle()
                            .appCinematicReveal(delay: 0.19)
                .frame(width: 184, height: 184)
                        homeShortcutsPanel
                            .appCinematicReveal(delay: 0.25)
                        .fill(PlatinumPalette.neonBlue)
                        .frame(width: 3, height: 12)
                            .appCinematicReveal(delay: 0.31)
                }
                .rotationEffect(.degrees(heroRingRotation * 0.55))
                            .appCinematicReveal(delay: 0.37)
            LinearGradient(
                colors: [AppTheme.pageBackground.opacity(0.98), AppTheme.pageBackground.opacity(0.84), AppTheme.pageBackground.opacity(0.30), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Capsule()
                        .fill(PlatinumPalette.neonBlue)
                        .frame(width: 19, height: 3)
                    Text("TryStore · Free Fire MAX")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PlatinumPalette.neonBlue)
                        .dashboardTextMotion(delay: 0.08)
                }
                VStack(alignment: .leading, spacing: -2) {
                    StaggeredDashboardTitle(text: "Free Fire", font: .system(size: 23, weight: .medium, design: .serif), color: .white.opacity(0.88))
                    StaggeredDashboardTitle(text: "MAX", font: .system(size: 48, weight: .bold, design: .serif), color: .white)
                }
                Rectangle()
                    .fill(LinearGradient(colors: [PlatinumPalette.neonBlue.opacity(0.82), Color.cyan.opacity(0.30), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                Text("Loadouts, visuals, and device status.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                    .dashboardTextMotion(delay: 0.18)
                HStack(spacing: 6) {
                    heroBadge(icon: "gamecontroller.fill", title: "Max only")
                    heroBadge(icon: "sparkles", title: "Visuals")
                }
            }
            .padding(18)
            .padding(.trailing, 132)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 244, height: 294)
                .offset(x: 17, y: 24 + (heroFloat ? -4 : 3))
                .scaleEffect(heroFloat ? 1.015 : 0.99)
                .animation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true), value: heroFloat)
                .shadow(color: PlatinumPalette.neonBlue.opacity(0.34), radius: heroFloat ? 25 : 14, y: 7)
                .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [PlatinumPalette.neonBlue.opacity(0.76), Color.white.opacity(0.08), Color.cyan.opacity(0.40), Color.white.opacity(0.08), PlatinumPalette.neonBlue.opacity(0.76)],
                        center: .center,
                        startAngle: .degrees(heroRingRotation),
                        endAngle: .degrees(heroRingRotation + 360)
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, PlatinumPalette.neonBlue.opacity(0.12), Color.white.opacity(0.20), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 32)
                .rotationEffect(.degrees(18))
                .offset(x: heroScan ? proxy.size.width + 42 : -55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .allowsHitTesting(false)
        }
        .shadow(color: PlatinumPalette.neonBlue.opacity(0.14), radius: 22, y: 9)
        .padding(.bottom, 27)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) {
                heroFloat = true
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                heroRingRotation = 360
            }
            withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: false)) {
                heroScan = true
            }
        }
    }

    private func heroBadge(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.76))
            .dashboardTextMotion(delay: 0.28)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var characterCompatibilityPanel: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accent.opacity(0.18), AppTheme.electricBlue, AppTheme.accent.opacity(0.18)],
                            center: .center
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(characterRingRotation))
                Image("CleanCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 60)
                    .offset(y: 4)
                    .shadow(color: AppTheme.electricBlue.opacity(0.28), radius: 8, y: 2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Character compatibility")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                Text(characterCompatibilityStatus)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.accent.opacity(0.84))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: characterCompatibilitySymbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(characterModuleItem == nil && !patchStore.isBusy ? Color.orange : AppTheme.accent)
                .shadow(color: AppTheme.electricBlue.opacity(0.42), radius: 7)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, AppTheme.electricBlue.opacity(0.42), AppTheme.accent.opacity(0.30), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                characterRingRotation = 360
            }
        }
    }

    private var characterModuleItem: PatchLibraryItem? {
        let projectName = "HOLOGRAMA PERSONAJE"
        return patchStore.items.first {
            $0.project?.name == projectName
                || $0.packageURL.lastPathComponent.caseInsensitiveCompare("\(projectName).3105") == .orderedSame
        }
    }

    private var characterCompatibilityStatus: String {
        guard appState.isSupported else { return "Device compatibility needs review" }
        if patchStore.isBusy { return "Checking character module…" }
        guard let characterModuleItem else { return "Character module unavailable" }
        return DevicePatchService.latestReceipt(projectID: characterModuleItem.id) == nil
            ? "Character module ready for this device"
            : "Character visual is active"
    }

    private var characterCompatibilitySymbol: String {
        if !appState.isSupported { return "exclamationmark.triangle.fill" }
        if patchStore.isBusy { return "arrow.triangle.2.circlepath" }
        return characterModuleItem == nil ? "xmark.circle.fill" : "checkmark.seal.fill"
    }

    private var telemetryStrip: some View {
        HStack(spacing: 8) {
            telemetryCell(icon: "iphone", label: "Device", value: AppInfo.displayMachineName)
            telemetryCell(icon: "gearshape.2.fill", label: "iOS", value: AppInfo.osVersion)
            telemetryCell(icon: "shield.lefthalf.filled", label: "Status", value: appState.isSupported ? "Supported" : "Review")
        }
    }

    private func telemetryCell(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
                .dashboardTextMotion(delay: 0.04)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .dashboardTextMotion(delay: 0.08)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 11)
        .dashboardGlass(cornerRadius: 14, tint: .cyan)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "Device overview", subtitle: "Live system status", icon: "iphone.gen3")
            statusRow(title: language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
            statusRow(title: language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
            HStack {
                Text(language.text("settings.exploit_compatibility"))
                    .foregroundStyle(.white.opacity(0.62))
                    .dashboardTextMotion(delay: 0.06)
                Spacer()
                Text(language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"))
                    .fontWeight(.bold)
                    .foregroundStyle(appState.isSupported ? .green : .orange)
                    .dashboardTextMotion(delay: 0.10)
            }
            .font(.system(size: 12, design: .rounded))
            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                statusRow(
                    title: language.text("dashboard.kernel_status"),
                    value: appState.kernelExploitRunning
                        ? language.text("dashboard.kernel_running")
                        : language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive")
                )
            }
        }
        .padding(14)
        .dashboardGlass(cornerRadius: 21, tint: .cyan)
    }

    private var quickStartPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "Getting started", subtitle: "Manage your patches", icon: "sparkles")
            HStack(alignment: .top, spacing: 8) {
                quickStartStep(number: "01", title: "OPEN", detail: "Choose Patches below")
                quickStartStep(number: "02", title: "REVIEW", detail: "Select a patch project")
                quickStartStep(number: "03", title: "APPLY", detail: "Restore originals any time")
            }
        }
        .padding(14)
        .dashboardGlass(cornerRadius: 21, tint: .orange)
    }

    private func quickStartStep(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .dashboardTextMotion(delay: 0.02)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .dashboardTextMotion(delay: 0.06)
            Text(detail)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
                .dashboardTextMotion(delay: 0.10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var characterPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(title: "Character preview", subtitle: "TryStore classic art", icon: "person.fill")
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.02, green: 0.08, blue: 0.17), Color.black.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image("TryStoreTheme")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .opacity(0.09)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Image("CleanCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 230)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: previewFloat ? -4 : 4)
                    .scaleEffect(previewFloat ? 1.015 : 0.99)
                    .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: previewFloat)
                    .shadow(color: AppTheme.accent.opacity(0.32), radius: previewFloat ? 25 : 14, y: 6)
                Label("FREE FIRE MAX", systemImage: "gamecontroller.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .dashboardTextMotion(delay: 0.08)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.70), in: Capsule())
                    .padding(12)
            }
            .frame(height: 226)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.75), Color.white.opacity(0.08), Color.cyan.opacity(0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                previewFloat = true
            }
        }
        .padding(14)
        .dashboardGlass(cornerRadius: 23, tint: .cyan)
    }

    private var legacyPatchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.accent.opacity(0.24), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Patch library")
                                        .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundStyle(.white)
                                .dashboardTextMotion(delay: 0.04)
                            Text("Free Fire MAX · 6 modules")
                                        .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(AppTheme.accent)
                                .dashboardTextMotion(delay: 0.08)
                        }
                    }
                }
                Spacer()
                if patchStore.isBusy {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .scaleEffect(0.78)
                        .accessibilityLabel("Applying patch")
                } else {
                    Text("\(activeLegacyPatchCount) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .dashboardTextMotion(delay: 0.12)
                        .padding(.horizontal, 9)
                                .frame(height: 30)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }

            PlatinumExpiryCard(
                expirationDate: licenseManager.expirationDate,
                isActive: licenseManager.isActive
            )

            HStack(spacing: 7) {
                ForEach(DashboardPatchTab.allCases) { tab in
                    let selected = selectedPatchTab == tab
                    Button {
                        guard selectedPatchTab != tab else { return }
                        AppHaptics.select()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                            selectedPatchTab = tab
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color.cyan, PlatinumPalette.bright, Color(red: 0.66, green: 0.94, blue: 1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .matchedGeometryEffect(id: "platinum-patch-tab", in: patchTabNamespace)
                            }
                            Label(tab.title, systemImage: tab.icon)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(selected ? PlatinumPalette.graphite : Color.white.opacity(0.62))
                                .dashboardTextMotion(delay: selected ? 0.02 : 0.08)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? PlatinumPalette.bright.opacity(0.82) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlatinumPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            if selectedPatchTab == .visuals {
                visualPatchPreview
            }

            VStack(spacing: 7) {
                let options = selectedPatchTab == .loadout ? DashboardPatchOption.loadout : DashboardPatchOption.visuals
                ForEach(options.indices, id: \.self) { index in
                    legacyPatchButton(options[index])
                        .appCinematicReveal(delay: Double(index) * 0.055)
                }
            }
            .id(selectedPatchTab)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            if selectedPatchTab == .loadout {
                Text("Aim modules share a file; only one can be active at a time.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
                    .dashboardTextMotion(delay: 0.18)
            }
        }
        .padding(14)
        .dashboardGlass(cornerRadius: 23, tint: .cyan)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                patchSheen = true
            }
        }
    }

    private var visualPatchPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.03, green: 0.13, blue: 0.27), Color.black.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(height: 132)
                .frame(maxWidth: .infinity, alignment: .center)
                .shadow(color: AppTheme.accent.opacity(0.22), radius: 14, y: 4)
            Label("TryStore classic character", systemImage: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .dashboardTextMotion(delay: 0.08)
                .padding(10)
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.20), lineWidth: 1))
    }

    private func legacyPatchButton(_ option: DashboardPatchOption) -> some View {
        let activeTint = AppTheme.accent
        let item = patchStore.items.first {
            $0.project?.name == option.projectName
                || $0.packageURL.lastPathComponent.caseInsensitiveCompare("\(option.projectName).3105") == .orderedSame
        }
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false

        return Button {
            guard let item else { return }
            AppHaptics.tap()
            patchStore.setEnabled(!isActive, for: item, group: option.group, reportsSuccess: false, onSuccess: { enabled in PatchAudioFeedback.play(enabled: enabled) })
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? PlatinumPalette.graphite : option.color)
                    .frame(width: 40, height: 40)
                    .background(
                        (isActive ? activeTint : option.color.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .dashboardTextMotion(delay: 0.04)
                    Text(option.group.map { _ in "Loadout module" } ?? "Visual module")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.52))
                        .dashboardTextMotion(delay: 0.08)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isActive {
                        Circle()
                            .fill(PlatinumPalette.graphite)
                            .frame(width: 4, height: 4)
                            .shadow(color: .white.opacity(0.8), radius: 3)
                    }
                    Text(item == nil ? "Unavailable" : (isActive ? "On" : "Off"))
                        .font(.system(size: 11, weight: .semibold))
                        .dashboardTextMotion(delay: 0.12)
                }
                .foregroundStyle(item == nil ? Color.orange : (isActive ? PlatinumPalette.graphite : Color.white.opacity(0.56)))
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 28)
                .background(
                    isActive
                        ? LinearGradient(colors: [activeTint, Color.cyan.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isActive ? Color.white.opacity(0.70) : Color.white.opacity(0.08), lineWidth: 0.8))
                .shadow(color: isActive ? activeTint.opacity(0.45) : .clear, radius: 9, y: 1)
                Image(systemName: item == nil ? "exclamationmark.triangle.fill" : (isActive ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item == nil ? .orange : (isActive ? PlatinumPalette.silver : .white.opacity(0.30)))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(
                        colors: isActive
                            ? [activeTint.opacity(0.36), Color.cyan.opacity(0.17), PlatinumPalette.silver.opacity(0.10)]
                            : [Color.cyan.opacity(0.10), Color.white.opacity(0.035), Color.black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                        ))
                    }
            }
            .overlay {
                if isActive && !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .rotationEffect(.degrees(22))
                    .offset(x: patchSheen ? 180 : -180)
                    .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isActive
                            ? LinearGradient(colors: [Color.white.opacity(0.96), activeTint.opacity(0.92), Color.cyan.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: isActive ? activeTint.opacity(0.25) : .clear, radius: 16, y: 4)
            .scaleEffect(isActive ? 1.018 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.68), value: isActive)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(patchStore.isBusy || item == nil)
        .opacity(patchStore.isBusy ? 0.72 : (item == nil ? 0.52 : 1))
        .buttonStyle(PlatinumPressStyle())
        .accessibilityLabel("\(option.title), \(isActive ? "on" : "off")")
    }

    private var activeLegacyPatchCount: Int {
        DashboardPatchOption.all.reduce(into: 0) { count, option in
            guard let item = patchStore.items.first(where: { $0.project?.name == option.projectName }),
                  DevicePatchService.latestReceipt(projectID: item.id) != nil else { return }
            count += 1
        }
    }

    private var socialLinksPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "Follow TryStore", subtitle: "Official social links", icon: "person.2.fill")
            HStack(spacing: 9) {
                socialLinkCard(
                    title: "TikTok",
                    handle: "@vaal_goat",
                    icon: "play.rectangle.fill",
                    colors: [.black, AppTheme.electricBlue],
                    url: "https://www.tiktok.com/@vaal_goat"
                )
                socialLinkCard(
                    title: "Instagram",
                    handle: "@guillenrmarcos",
                    icon: "camera.fill",
                    colors: [AppTheme.electricBlue, AppTheme.accent],
                    url: "https://www.instagram.com/guillenrmarcos"
                )
            }
        }
        .padding(14)
        .dashboardGlass(cornerRadius: 22, tint: AppTheme.electricBlue)
    }

    private func socialLinkCard(title: String, handle: String, icon: String, colors: [Color], url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .dashboardTextMotion(delay: 0.06)
                Text(handle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dashboardTextMotion(delay: 0.10)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PlatinumPressStyle())
        .accessibilityLabel("Open TryStore \(title) profile \(handle)")
    }

    private var footerBar: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, AppTheme.accent.opacity(0.45), .clear],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, 36)
            .padding(.top, 5)
    }

    private func panelHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .dashboardTextMotion(delay: 0.06)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))
                    .dashboardTextMotion(delay: 0.10)
            }
            Spacer()
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.57))
                .dashboardTextMotion(delay: 0.04)
            Spacer(minLength: 10)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.trailing)
                .dashboardTextMotion(delay: 0.08)
        }
            .font(.system(size: 13, design: .default))
    }
}

private struct TryStoreAmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @State private var drift = false
    let touchPoint: CGPoint
    let touchStrength: Double

    private let particleColors: [Color] = [AppTheme.accent, AppTheme.electricBlue, .cyan, .blue]

    init(touchPoint: CGPoint = .zero, touchStrength: Double = 0) {
        self.touchPoint = touchPoint
        self.touchStrength = touchStrength
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.008, green: 0.022, blue: 0.052), AppTheme.pageBackground, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image("TryStoreTheme")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340)
                .opacity(0.025)
                .blur(radius: 5)
            Circle()
                .fill(AppTheme.accent.opacity(0.10))
                .frame(width: 270, height: 270)
                .blur(radius: 72)
                .offset(
                    x: (drift ? 118 : 155) + CGFloat(deviceTilt.roll) * 20,
                    y: (drift ? -275 : -320) - CGFloat(deviceTilt.pitch) * 17
                )
                .scaleEffect(drift ? 1.12 : 0.92)
            Circle()
                .fill(Color.blue.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 68)
                .offset(
                    x: (drift ? -105 : -150) + CGFloat(deviceTilt.roll) * 13,
                    y: (drift ? 220 : 275) - CGFloat(deviceTilt.pitch) * 12
                )
                .scaleEffect(drift ? 0.9 : 1.12)
            Circle()
                .fill(Color.cyan.opacity(0.045))
                .frame(width: 180, height: 180)
                .blur(radius: 62)
                .offset(x: drift ? 155 : 105, y: drift ? 380 : 430)
                .scaleEffect(drift ? 1.15 : 0.88)
            Circle()
                .fill(AppTheme.electricBlue.opacity(0.075))
                .frame(width: 245, height: 245)
                .blur(radius: 78)
                .offset(x: drift ? -175 : -115, y: drift ? -95 : -165)
                .scaleEffect(drift ? 1.10 : 0.88)
            Circle()
                .fill(AppTheme.accent.opacity(0.045))
                .frame(width: 185, height: 185)
                .blur(radius: 72)
                .offset(x: drift ? 120 : 180, y: drift ? 285 : 350)
                .scaleEffect(drift ? 0.92 : 1.12)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || touchStrength < 0.01)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(touchStrength * 0.26),
                            AppTheme.electricBlue.opacity(touchStrength * 0.18),
                            AppTheme.accent.opacity(touchStrength * 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 205
                    )

                    Circle()
                        .stroke(Color.white.opacity(touchStrength * 0.24), lineWidth: 1)
                        .frame(width: 92, height: 92)
                        .scaleEffect(reduceMotion ? 1 : 0.82 + CGFloat((sin(time * 3.2) + 1) * 0.10))
                        .position(touchPoint)

                    if !reduceMotion {
                        ForEach(0..<15, id: \.self) { index in
                            particleView(index: index, time: time)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(touchStrength)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func particleView(index: Int, time: TimeInterval) -> some View {
        let angle: Double = Double(index) * (.pi * 2 / 15)
            + time * (index.isMultiple(of: 2) ? 0.48 : -0.34)
        let radius: CGFloat = CGFloat(34 + (index % 5) * 14)
        let color = particleColors[index % particleColors.count]
        let diameter: CGFloat = index.isMultiple(of: 4) ? 4.5 : 2.5
        let opacity = touchStrength * (index.isMultiple(of: 3) ? 0.9 : 0.58)

        return Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(0.7), radius: 5)
            .position(
                x: touchPoint.x + CGFloat(cos(angle)) * radius,
                y: touchPoint.y + CGFloat(sin(angle)) * radius
            )
            .opacity(opacity)
    }
}

private extension FreeFireGame {
    var scheme: String {
        "freefiremax"
    }

    var titleKey: String {
        "freefire.title"
    }

    var artworkName: String {
        "FreeFireMax"
    }

    var aimProjectNames: [String] {
        ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO"]
    }

    var locationProjectNames: [String] {
        ["HOLOGRAMA ARMAS", "HOLOGRAMA PERSONAJE"]
    }

    var openGameKey: String {
        "freefire.open_game"
    }

    func canOpen() -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

// MARK: - FreeFireGameEntryView
private struct FreeFireGameEntryView: View {
    @Environment(\.appLanguage) private var language
    let game: FreeFireGame
    @State private var isAvailable: Bool
    @State private var showNotice = false
    @State private var navigateToPatch = false

    init(game: FreeFireGame) {
        self.game = game
        _isAvailable = State(initialValue: game.canOpen())
    }

    var body: some View {
        Button {
            showNotice = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.12))
                    FreeFireArtwork(game: game, size: 56)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text(game.titleKey))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(isAvailable ? .white : .white.opacity(0.48))
                    Text(isAvailable ? "OPEN MAX PATCH CONSOLE" : language.text("dashboard.unavailable"))
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.55)
                        .foregroundStyle(isAvailable ? AppTheme.accent : .orange)
                }
                Spacer(minLength: 5)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(red: 0.045, green: 0.15, blue: 0.30), Color.black.opacity(0.56)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(AppTheme.accent.opacity(0.35), lineWidth: 1))
            .opacity(isAvailable ? 1 : 0.68)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .navigationDestination(isPresented: $navigateToPatch) {
            FreeFirePatchView(game: game)
        }
        .alert(language.text("freefire.notice_title"), isPresented: $showNotice) {
            Button(language.text("freefire.notice_confirm")) {
                navigateToPatch = true
            }
        } message: {
            Text(language.text("freefire.notice_message"))
        }
        .tint(AppTheme.accent)
        .onAppear {
            isAvailable = game.canOpen()
        }
    }
}

// MARK: - FreeFirePatchView
private struct FreeFirePatchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var licenseManager: LicenseManager
    let game: FreeFireGame
    @StateObject private var store: PatchProjectStore
    @State private var selectedSegment = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isGameAvailable: Bool

    init(game: FreeFireGame) {
        self.game = game
        _store = StateObject(wrappedValue: PatchProjectStore(game: game))
        _isGameAvailable = State(initialValue: game.canOpen())
    }

    // MARK: - Hàm lấy danh sách item
    private var aimItems: [PatchLibraryItem] {
        let names = game.aimProjectNames
        return names.compactMap { name in
            store.items.first { item in
                item.project?.name == name
            }
        }
    }

    private var locationItems: [PatchLibraryItem] {
        let names = game.locationProjectNames
        var seen: Set<UUID> = []
        return names.compactMap { name in
            let expectedName = normalizedLocationProjectName(name)
            guard let match = store.items.first(where: { item in
                let currentName = item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent
                return normalizedLocationProjectName(currentName) == expectedName
            }) else { return nil }
            if seen.insert(match.id).inserted { return match }
            return nil
        }
    }

    private func normalizedLocationProjectName(_ name: String) -> String {
        let latinized = name
            .replacingOccurrences(of: "Đ", with: "D")
            .replacingOccurrences(of: "đ", with: "d")
        let folded = latinized.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }

    // MARK: - Display Name
    private func aimDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "HEAD": return "HEAD"
        case "NECK": return "NECK"
        case "HS PESSCOSO": return "DRAG"
        case "HS SLA PECHO": return "PECHO"
        default: return item.project?.name ?? language.text("freefire.aim_file")
        }
    }

    private func locationDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "HOLOGRAMA ARMAS": return "HOLOGRAMA ARMAS"
        case "HOLOGRAMA PERSONAJE": return "HOLOGRAMA PERSONAJE"
        default: return item.project?.name ?? language.text("freefire.location")
        }
    }

    private func patchToggleCard(
        _ item: PatchLibraryItem,
        title: String,
        icon: String,
        group: PatchToggleGroup
    ) -> some View {
        let isActive = DevicePatchService.latestReceipt(projectID: item.id) != nil
        let activeTint = AppTheme.accent

        return Toggle(isOn: Binding(
            get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
            set: { enabled in
                store.setEnabled(
                    enabled,
                    for: item,
                    group: group,
                    onSuccess: { state in PatchAudioFeedback.play(enabled: state) }
                )
            }
        )) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? activeTint : AppTheme.accent)
                    .frame(width: 29, height: 29)
                    .background((isActive ? activeTint : AppTheme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 3)
                Text(isActive ? "ON" : "OFF")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(isActive ? PlatinumPalette.graphite : Color.white.opacity(0.55))
                    .padding(.horizontal, 7)
                    .frame(minHeight: 20)
                    .background(isActive ? activeTint : Color.white.opacity(0.06), in: Capsule())
            }
        }
        .tint(isActive ? activeTint : AppTheme.accent)
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isActive
                      ? LinearGradient(colors: [activeTint.opacity(0.18), Color.cyan.opacity(0.07), AppTheme.consoleBackground], startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [Color.white.opacity(0.055), AppTheme.consoleBackground.opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isActive ? activeTint.opacity(0.72) : AppTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: isActive ? activeTint.opacity(0.16) : .clear, radius: 14, y: 4)
        .scaleEffect(isActive ? 1.008 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.76), value: isActive)
        .disabled(store.isBusy)
    }

    private var patchHeroPanel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text("TRY STORE / CONTROL DECK")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(AppTheme.accent)
                Text("FREE FIRE MAX")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 102)
                .shadow(color: AppTheme.accent.opacity(0.22), radius: 12, y: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(LinearGradient(
            colors: [Color(red: 0.045, green: 0.15, blue: 0.31), AppTheme.consoleBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.accent.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            TryStoreAmbientBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 13) {
                    patchHeroPanel.appCinematicReveal(delay: 0.04)
                    PlatinumExpiryCard(
                        expirationDate: licenseManager.expirationDate,
                        isActive: licenseManager.isActive
                    )
                    .appCinematicReveal(delay: 0.10)
                    if isLoading {
                        ProgressView(language.text("freefire.loading"))
                            .tint(AppTheme.accent)
                            .padding(.vertical, 40)
                    } else if let error = loadError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.consoleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Picker(language.text("freefire.patch_type"), selection: $selectedSegment) {
                            Label(language.text("freefire.aim_file"), systemImage: "scope").tag(0)
                            Label(language.text("freefire.location"), systemImage: "location.fill").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .tint(AppTheme.accent)
                        .appCinematicReveal(delay: 0.16)

                        if store.isBusy {
                            ProgressView(language.text("patch.operation_in_progress"))
                                .font(.footnote)
                                .tint(AppTheme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }

                        if selectedSegment == 0 {
                            if aimItems.isEmpty {
                                emptyPatchNotice
                            }
                            ForEach(aimItems) { item in
                                patchToggleCard(item, title: aimDisplayName(for: item), icon: "scope", group: .aim)
                                    .appCinematicReveal(delay: 0.22)
                                    .appGyroTilt(intensity: 0.78)
                            }
                        } else {
                            if locationItems.isEmpty {
                                emptyPatchNotice
                            }
                            ForEach(locationItems) { item in
                                patchToggleCard(item, title: locationDisplayName(for: item), icon: "location.fill", group: .location)
                                    .appCinematicReveal(delay: 0.22)
                                    .appGyroTilt(intensity: 0.78)
                            }
                        }

                        Button {
                            guard let url = URL(string: "\(game.scheme)://") else { return }
                            if isGameAvailable {
                                openURL(url)
                            }
                        } label: {
                            Label(
                                isGameAvailable ? language.text(game.openGameKey) : language.text("dashboard.unavailable"),
                                systemImage: isGameAvailable ? "gamecontroller.fill" : "gamecontroller"
                            )
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .tint(AppTheme.accent)
                        .disabled(!isGameAvailable)
                        .background(
                            isGameAvailable ? AppTheme.accent : Color.gray.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, 22)
            }
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(language.text(game.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            isGameAvailable = game.canOpen()
        }
        .task {
            await loadPatchLibrary()
        }
        .alert(item: $store.alert) { alert in
            let title = Text(language.text(alert.titleKey))
            let message = Text(alert.message(language: language))
            if alert.messageKey == "patch.error.pairing_tunnel_required" {
                return Alert(
                    title: title,
                    message: message,
                    primaryButton: .default(Text(language.text("settings.open_localdevvpn"))) {
                        if let url = URL(string: "localdevvpn://") {
                            openURL(url)
                        }
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel")))
                )
            }
            return Alert(
                title: title,
                message: message,
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private var emptyPatchNotice: some View {
        Text("No bundled Free Fire MAX patches are available in this category.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(AppTheme.consoleBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Hàm tải patch (chạy background)
    private func loadPatchLibrary() async {
        guard let key = licenseManager.patchBundleKey else {
            loadError = "Resource authorization is unavailable. Please refresh your license."
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        store.installBundledResources(bundleKey: key)
        store.reload()
        isLoading = false
    }

}

// MARK: - FreeFireArtwork
private struct FreeFireArtwork: View {
    let game: FreeFireGame
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: game.artworkName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private var fallbackArtwork: some View {
        Image(systemName: "gamecontroller.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.accent)
    }
}
