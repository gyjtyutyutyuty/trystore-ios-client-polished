import SwiftUI
import ActivityKit
import UIKit

@available(iOS 16.1, *)
struct LiveActivityState: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let isActive: Bool
        let cpuTemp: Double?
        let gpuTemp: Double?
        let thermalState: String?
        let launchCount: Int
    }
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onOpenPatches: { selectedTab = 1 })
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            PatchesView()
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("Patches")
                }
                .tag(1)
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    var onOpenPatches: () -> Void = {}
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var heroArrived = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBarHome.appCinematicReveal(delay: 0.02)
                        heroHome.appCinematicReveal(delay: 0.08)
                        vitalPanelHome.appCinematicReveal(delay: 0.15)
                        quickAccessHome.appCinematicReveal(delay: 0.21)
                        deviceSectionHome.appCinematicReveal(delay: 0.27)
                        quickStartPanelHome.appCinematicReveal(delay: 0.33)
                        footerHome.appCinematicReveal(delay: 0.39)
                    }
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppTheme.accent)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
    }

    // MARK: - Header

    private var topBarHome: some View {
        HStack(spacing: AppSpacing.m) {
            AppLogo(size: horizontalSizeClass == .compact ? 38 : 46)
                .padding(3)
                .background(AppPalette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("TRY STORE")
                    .font(.system(size: horizontalSizeClass == .compact ? 16 : 19, weight: .black, design: .rounded))
                    .tracking(horizontalSizeClass == .compact ? 1.0 : 1.6)
                    .foregroundStyle(AppPalette.textPrimary)
                Text("MAX CONTROL  /  VISUAL LAB")
                    .font(AppType.label())
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
            }

            Spacer(minLength: AppSpacing.xs)

            headerButtonHome(icon: "apple.terminal", label: language.text("accessibility.open_logs")) {
                showLogs = true
            }
            headerButtonHome(icon: "slider.horizontal.3", label: language.text("accessibility.open_settings")) {
                showSettings = true
            }
        }
    }

    private func headerButtonHome(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppPalette.raised.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(AppPalette.hairline.opacity(0.65), lineWidth: 1))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Hero

    private var heroHome: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .stroke(AppTheme.accent.opacity(0.10), lineWidth: 1)
                .frame(width: 190, height: 190)
                .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 1).padding(20))
                .overlay {
                    Image(systemName: "scope")
                        .font(.system(size: 66, weight: .ultraLight))
                        .foregroundStyle(AppTheme.accent.opacity(0.18))
                        .rotationEffect(.degrees(heroArrived ? 12 : -12))
                }
                .offset(x: 70, y: -46)
                .appGyroTilt(intensity: 0.9)

            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(spacing: AppSpacing.s) {
                    Circle()
                        .fill(appState.isSupported ? AppPalette.mint : AppPalette.amber)
                        .frame(width: 7, height: 7)
                        .shadow(color: appState.isSupported ? AppPalette.mint : AppPalette.amber, radius: 6)
                    Text(appState.isSupported ? "SYSTEM READY" : "CHECK DEVICE STATUS")
                        .font(AppType.label())
                        .tracking(0.9)
                        .foregroundStyle(AppPalette.textPrimary)
                }
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(Color.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR PATCH\nCONTROL CENTER")
                        .font(AppType.hero(horizontalSizeClass == .compact))
                        .tracking(-0.2)
                        .lineSpacing(-2)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("Manage modules, connections, and device health from one focused workspace.")
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 320, alignment: .leading)

                AppActionButton(title: "EXPLORE PATCH STUDIO", icon: "arrow.up.right") {
                    onOpenPatches()
                }
                .frame(maxWidth: 264)
                .accessibilityHint("Switches to the Patches tab")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.l + 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.043, green: 0.176, blue: 0.216), AppPalette.surface, AppPalette.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppTheme.accent.opacity(0.34),
                            Color.white.opacity(0.06),
                            AppPalette.hairline.opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .onAppear {
            guard !reduceMotion else {
                heroArrived = true
                return
            }
            withAnimation(AppMotion.settle) { heroArrived = true }
        }
    }

    // MARK: - Vitals

    private var thermalProgress: Double {
        switch appState.thermalStateLabel {
        case "Nominal": return 0.28
        case "Fair": return 0.55
        case "Serious": return 0.78
        case "Critical": return 1.0
        default: return 0.08
        }
    }

    private var thermalTint: Color {
        switch appState.thermalStateLabel {
        case "Nominal": return AppPalette.mint
        case "Fair": return AppPalette.amber
        case "Serious", "Critical": return AppPalette.coral
        default: return AppPalette.textTertiary
        }
    }

    private var vitalPanelHome: some View {
        HStack(alignment: .center, spacing: AppSpacing.l) {
            AppRingGauge(
                progress: thermalProgress,
                value: appState.thermalStateLabel,
                caption: "THERMAL",
                tint: thermalTint
            )

            VStack(alignment: .leading, spacing: AppSpacing.m) {
                AppSectionHeader(
                    icon: "waveform.path.ecg",
                    title: "DEVICE VITALS",
                    subtitle: "LIVE SYSTEM STATE",
                    tint: thermalTint
                )
                VStack(spacing: AppSpacing.s) {
                    vitalRow(
                        icon: "clock.arrow.circlepath",
                        label: language.text("dashboard.launch_count"),
                        value: "\(appState.totalLaunches)",
                        tint: AppTheme.accent
                    )
                    vitalRow(
                        icon: "checkmark.shield.fill",
                        label: language.text("settings.exploit_compatibility"),
                        value: language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"),
                        tint: appState.isSupported ? AppPalette.mint : AppPalette.amber
                    )
                    vitalRow(
                        icon: "star.fill",
                        label: "FAVORITES",
                        value: "\(appState.favorites.count)",
                        tint: AppPalette.amber
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func vitalRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: AppSpacing.s)
            Text(value)
                .font(AppType.label())
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Quick access

    private var quickAccessHome: some View {
        HStack(spacing: AppSpacing.m) {
            quickAccessCardHome(icon: "apple.terminal", title: "LOGS", detail: "Recent activity") {
                showLogs = true
            }
            .accessibilityLabel(language.text("accessibility.open_logs"))

            quickAccessCardHome(icon: "slider.horizontal.3", title: "CONNECTIONS", detail: "Airlift and VPN") {
                showSettings = true
            }
            .accessibilityLabel("Open Airlift and VPN settings")
        }
    }

    private func quickAccessCardHome(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                AppIconBadge(systemName: icon, tint: AppTheme.accent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppType.label())
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text(detail)
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(AppSpacing.m)
            .appPanel(radius: AppRadius.tile)
        }
        .buttonStyle(AppPressButtonStyle())
    }

    // MARK: - Device

    private var deviceSectionHome: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(icon: "iphone.gen3", title: "SYSTEM SNAPSHOT", subtitle: "LIVE DEVICE HEALTH")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.m),
                    GridItem(.flexible(), spacing: AppSpacing.m)
                ],
                spacing: AppSpacing.m
            ) {
                AppMetricTile(
                    icon: "iphone.gen3",
                    label: language.text("dashboard.hardware_model"),
                    value: AppInfo.displayMachineName,
                    tint: AppTheme.accent
                )
                AppMetricTile(
                    icon: "gearshape.2.fill",
                    label: language.text("settings.ios_version"),
                    value: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))",
                    tint: AppTheme.accentSecondary
                )
                AppMetricTile(
                    icon: "thermometer.medium",
                    label: "THERMAL",
                    value: appState.thermalStateLabel,
                    tint: thermalTint
                )
                AppMetricTile(
                    icon: "checkmark.shield.fill",
                    label: language.text("settings.exploit_compatibility"),
                    value: language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"),
                    tint: appState.isSupported ? AppPalette.mint : AppPalette.amber
                )
            }

            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                statusRow(
                    title: language.text("dashboard.kernel_status"),
                    value: appState.kernelExploitRunning
                        ? language.text("dashboard.kernel_running")
                        : language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive")
                )
            }

            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppPalette.textTertiary)
                Text("Thermal state is shown; iOS does not expose raw CPU/GPU temperatures.")
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppType.meta())
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            Text(title)
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textSecondary)
            Spacer(minLength: AppSpacing.s)
            Text(value)
                .font(AppType.label())
                .foregroundStyle(AppPalette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Start here

    private var quickStartPanelHome: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(icon: "bolt.fill", title: "START HERE", subtitle: "THREE STEPS TO A PATCH")

            VStack(spacing: AppSpacing.s) {
                quickStartStepHome(number: "01", title: "Choose a category", detail: "Select LOADOUT or VISUALS.")
                quickStartStepHome(number: "02", title: "Activate a patch", detail: "Select a module, then tap ACTIVATE PATCH.")
                quickStartStepHome(number: "03", title: "Restore safely", detail: "Use RESTORE PATCH when you are finished.")
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func quickStartStepHome(number: String, title: String, detail: String) -> some View {
        HStack(spacing: AppSpacing.m) {
            Text(number)
                .font(AppType.digits(13))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppType.body())
                    .foregroundStyle(AppPalette.textPrimary)
                Text(detail)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, AppSpacing.m)
        .background(AppPalette.raised.opacity(0.42), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }

    // MARK: - Footer

    private var footerHome: some View {
        VStack(spacing: AppSpacing.m) {
            AppHairline()
            Text("TRY STORE  •  SUPPORT PATCH")
                .font(AppType.label())
                .tracking(1.2)
                .foregroundStyle(AppPalette.textTertiary)
        }
    }
}

// MARK: - PatchesView
private enum DashboardPatchTab: String, CaseIterable, Identifiable {
    case loadout
    case visuals

    var id: String { rawValue }
    var title: String { self == .loadout ? "LOADOUT" : "VISUALS" }
    var icon: String { self == .loadout ? "scope" : "sparkles" }
}

/// Legacy "platinum" tones, retuned to the shared palette so the older panels
/// and pills read as part of the same surface family instead of a second theme.
private enum PlatinumPalette {
    static let bright = AppPalette.textPrimary
    static let silver = AppPalette.textSecondary
    static let graphite = Color(red: 0.02, green: 0.07, blue: 0.07)
    static let gunmetal = AppPalette.raised
}

private struct PlatinumPressStyle: ButtonStyle {
    @Environment(\.appReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.055 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

private struct PlatinumExpiryCard: View {
    let expirationDate: Date?
    let isActive: Bool

    @Environment(\.appReduceMotion) private var reduceMotion
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PlatinumPalette.bright)
            }
            .frame(width: 44, height: 44)
            .shadow(color: PlatinumPalette.silver.opacity(0.32), radius: 9)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LICENSE WINDOW")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(PlatinumPalette.bright)
                    Spacer(minLength: 4)
                    Text(isActive ? "AUTHORIZED" : "VERIFYING")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(isActive ? PlatinumPalette.graphite : .white.opacity(0.76))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(isActive ? PlatinumPalette.bright : Color.white.opacity(0.12), in: Capsule())
                }

                if let expirationDate {
                    Text(expiryStamp(expirationDate))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(countdown(to: expirationDate, now: context.date))
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(0.65)
                            .foregroundStyle(PlatinumPalette.silver)
                            .monospacedDigit()
                    }
                } else {
                    Text("NO EXPIRY TIMESTAMP PROVIDED")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(PlatinumPalette.bright)
                    Text("The license service did not return an expiry date.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [PlatinumPalette.gunmetal, PlatinumPalette.graphite, Color.black.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
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
        .onChange(of: reduceMotion) { isReduced in
            if isReduced {
                sweep = false
                ringRotation = 0
            } else {
                withAnimation(.linear(duration: 4.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                    ringRotation = 360
                }
            }
        }
    }

    private func expiryStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter.string(from: date)
    }

    private func countdown(to expiry: Date, now: Date) -> String {
        let remaining = Int(expiry.timeIntervalSince(now))
        guard remaining > 0 else { return "EXPIRED" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        return String(format: "%02dD  %02dH  %02dM  %02dS REMAINING", days, hours, minutes, seconds)
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
        DashboardPatchOption(projectName: "HEAD", title: "HEAD", icon: "viewfinder", color: .indigo, group: .aim),
        DashboardPatchOption(projectName: "NECK", title: "NECK", icon: "scope", color: .cyan, group: .aim),
        DashboardPatchOption(projectName: "HS PESSCOSO", title: "DRAG", icon: "arrow.up.right.and.arrow.down.left", color: .orange, group: .aim),
        DashboardPatchOption(projectName: "HS SLA PECHO", title: "PECHO", icon: "scope", color: AppTheme.accent, group: .aim),
        DashboardPatchOption(projectName: "TryStore", title: "Balas Magicas", icon: "circle.grid.cross", color: .yellow, group: .aim)
    ]

    static let visuals = [
        DashboardPatchOption(projectName: "HOLOGRAMA EXCLUSIVO VERDE", title: "EXCLUSIVO VERDE", icon: "leaf.fill", color: .green, group: nil),
        DashboardPatchOption(projectName: "HOLOGRAMA EXCLUSIVO ROSADO", title: "EXCLUSIVO ROSADO", icon: "heart.fill", color: .pink, group: nil),
        DashboardPatchOption(projectName: "EXCLUSIVO AZUL", title: "Azul Exclusivo", icon: "flame.fill", color: .blue, group: nil)
    ]

    static var all: [DashboardPatchOption] { loadout + visuals }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var patchStore = PatchProjectStore(game: .max)
    @Namespace private var patchTabNamespace
    @State private var selectedPatchTab: DashboardPatchTab = .loadout
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var heroFloat = false
    @State private var heroRingRotation = 0.0
    @State private var heroScan = false
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
                    VStack(spacing: 14) {
                        topBar.appCinematicReveal(delay: 0.02).appGyroTilt(intensity: 0.40)
                        heroPanel.appCinematicReveal(delay: 0.08).appGyroTilt(intensity: 1.20)
                        telemetryStrip.appCinematicReveal(delay: 0.15).appGyroTilt(intensity: 0.48)
                        legacyPatchPanel.appCinematicReveal(delay: 0.22).appGyroTilt(intensity: 0.92)
                        deviceSection.appCinematicReveal(delay: 0.29).appGyroTilt(intensity: 0.62)
                        quickStartPanel.appCinematicReveal(delay: 0.36).appGyroTilt(intensity: 0.60)
                        characterPreviewPanel.appCinematicReveal(delay: 0.43).appGyroTilt(intensity: 0.82)
                        socialLinksPanel.appCinematicReveal(delay: 0.50).appGyroTilt(intensity: 0.42)
                        footerBar.appCinematicReveal(delay: 0.56).appGyroTilt(intensity: 0.30)
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
            .tint(AppTheme.accent)
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
        .tint(AppTheme.accent)
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
        HStack(spacing: horizontalSizeClass == .compact ? 6 : 11) {
            AppLogo(size: horizontalSizeClass == .compact ? 36 : 44)
                .padding(3)
                .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AppTheme.accent.opacity(0.36), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("TRY STORE")
                    .font(.system(size: horizontalSizeClass == .compact ? 15 : 18, weight: .black, design: .rounded))
                    .tracking(horizontalSizeClass == .compact ? 1.0 : 1.6)
                    .foregroundStyle(.white)
                Text("MAX CONTROL  /  VISUAL LAB")
                    .font(.system(size: 6, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(AppTheme.accent.opacity(0.82))
            }
            Spacer(minLength: 2)
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
            Text(appState.isSupported ? "READY" : "REVIEW")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(appState.isSupported ? .green : .orange)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.black.opacity(0.38), in: Capsule())
        .overlay(Capsule().stroke((appState.isSupported ? Color.green : Color.orange).opacity(0.34), lineWidth: 1))
        .accessibilityLabel(appState.isSupported ? "Device status ready" : "Device compatibility review required")
    }

    private func headerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: horizontalSizeClass == .compact ? 34 : 40, height: horizontalSizeClass == .compact ? 34 : 40)
                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(label)
    }

    private var heroPanel: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.045, green: 0.16, blue: 0.34), AppTheme.consoleBackground, AppTheme.pageBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(width: 150, height: 150)
                .blur(radius: 34)
                .offset(x: 38, y: -20)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.accent.opacity(0.02),
                            AppTheme.accent.opacity(0.92),
                            Color.white.opacity(0.72),
                            AppTheme.accent.opacity(0.08)
                        ],
                        center: .center,
                        startAngle: .degrees(heroRingRotation),
                        endAngle: .degrees(heroRingRotation + 360)
                    ),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3, 8])
                )
                .frame(width: 184, height: 184)
                .rotationEffect(.degrees(heroRingRotation * -0.35))
                .offset(x: 6, y: 5)
                .shadow(color: AppTheme.accent.opacity(0.45), radius: 9)
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
                .frame(width: 204, height: 204)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: 4, height: 15)
                        .shadow(color: AppTheme.accent, radius: 7)
                }
                .rotationEffect(.degrees(heroRingRotation * 0.55))
                .offset(x: 6, y: 5)
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 164, height: 210)
                .opacity(0.96)
                .offset(x: 5, y: heroFloat ? 2 : 11)
                .scaleEffect(heroFloat ? 1.025 : 0.985)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: heroFloat)
                .mask(LinearGradient(colors: [.white, .white.opacity(0.92), .clear], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 10) {
                Text("TRY STORE / CONTROL DECK")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.35)
                    .foregroundStyle(AppTheme.accent)
                Text("FREE FIRE\nMAX")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    heroBadge(icon: "gamecontroller.fill", title: "MAX ONLY")
                    heroBadge(icon: "sparkles", title: "VISUALS")
                }
            }
            .padding(17)
            .padding(.trailing, 112)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(minHeight: 208)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.accent.opacity(0.95),
                            Color.white.opacity(0.10),
                            AppTheme.accent.opacity(0.22),
                            Color.cyan.opacity(0.75),
                            AppTheme.accent.opacity(0.95)
                        ],
                        center: .center,
                        startAngle: .degrees(heroRingRotation),
                        endAngle: .degrees(heroRingRotation + 360)
                    ),
                    lineWidth: 1.25
                )
        }
        .overlay {
            GeometryReader { proxy in
                ZStack {
                    // Thin scan beam stays inside the card and never intercepts controls.
                    LinearGradient(
                        colors: [.clear, AppTheme.accent.opacity(0.14), Color.white.opacity(0.34), AppTheme.accent.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 42)
                    .rotationEffect(.degrees(18))
                    .offset(x: heroScan ? proxy.size.width + 65 : -75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            HeroCornerMark()
                .stroke(AppTheme.accent.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 22, height: 22)
                .padding(10)
                .shadow(color: AppTheme.accent.opacity(0.8), radius: 5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            HeroCornerMark()
                .stroke(AppTheme.accent.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(180))
                .padding(10)
                .shadow(color: AppTheme.accent.opacity(0.8), radius: 5)
                .allowsHitTesting(false)
        }
        .shadow(color: AppTheme.accent.opacity(0.22), radius: 26, y: 9)
        .onAppear {
            heroFloat = false
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                heroFloat = true
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                heroRingRotation = 360
            }
            withAnimation(.linear(duration: 5.8).repeatForever(autoreverses: false)) {
                heroScan = true
            }
        }
    }

    private func heroBadge(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 7, weight: .black, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(.white.opacity(0.76))
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var telemetryStrip: some View {
        HStack(spacing: 8) {
            telemetryCell(icon: "iphone", label: "DEVICE", value: AppInfo.displayMachineName)
            telemetryCell(icon: "gearshape.2.fill", label: "iOS", value: AppInfo.osVersion)
            telemetryCell(icon: "shield.lefthalf.filled", label: "STATUS", value: appState.isSupported ? "SUPPORTED" : "REVIEW")
        }
    }

    private func telemetryCell(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 47, alignment: .leading)
        .padding(.horizontal, 9)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "SYSTEM SNAPSHOT", subtitle: "LIVE DEVICE HEALTH", icon: "waveform.path.ecg")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                spacing: 9
            ) {
                deviceMetricCardHome(icon: "iphone.gen3", label: "DEVICE", value: AppInfo.displayMachineName, tint: AppTheme.accent)
                deviceMetricCardHome(icon: "gearshape.2.fill", label: "SOFTWARE", value: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))", tint: .cyan)
                deviceMetricCardHome(icon: "thermometer.medium", label: "THERMAL", value: appState.thermalStateLabel, tint: .orange)
                deviceMetricCardHome(
                    icon: "checkmark.shield.fill",
                    label: "COMPATIBILITY",
                    value: language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"),
                    tint: appState.isSupported ? .green : .orange
                )
            }
            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                statusRow(
                    title: language.text("dashboard.kernel_status"),
                    value: appState.kernelExploitRunning
                        ? language.text("dashboard.kernel_running")
                        : language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive")
                )
            }
            HStack(spacing: 8) {
            Text("Thermal state is shown; iOS does not expose raw CPU/GPU temperatures.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
            }
            HStack {
                Text(language.text("dashboard.launch_count"))
                    .foregroundStyle(.white.opacity(0.57))
                Spacer(minLength: 10)
                Text("\(appState.totalLaunches) times")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 9, design: .rounded))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppTheme.consoleBackground, Color.black.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))
    }
    private func temperatureRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(color)
            Label(label, systemImage: icon)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color.opacity(0.20), lineWidth: 0.5))
    }

    private var quickStartPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "QUICK START", subtitle: "YOUR MAX SESSION", icon: "bolt.fill")
            HStack(alignment: .top, spacing: 8) {
                quickStartStep(number: "01", title: "CHOOSE", detail: "Pick LOADOUT or VISUALS")
                quickStartStep(number: "02", title: "TOGGLE", detail: "Tap a legacy patch to apply")
                quickStartStep(number: "03", title: "RESTORE", detail: "Tap the active button again")
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func quickStartStep(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var characterPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(title: "CHARACTER PREVIEW", subtitle: "TRYSTORE CLASSIC ART", icon: "person.fill")
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
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.65)
                    .foregroundStyle(.white)
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
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                previewFloat = true
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.18), lineWidth: 1))
    }

    private var legacyPatchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRYSTORE PATCHES")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                    Text("FREE FIRE MAX  •  ORIGINAL MODULES")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.55)
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                if patchStore.isBusy {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .scaleEffect(0.78)
                        .accessibilityLabel("Applying patch")
                } else {
                    Text("\(activeLegacyPatchCount) / \(DashboardPatchOption.all.count) ACTIVE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
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
                                        colors: [PlatinumPalette.bright, PlatinumPalette.silver],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .matchedGeometryEffect(id: "platinum-patch-tab", in: patchTabNamespace)
                            }
                            Label(tab.title, systemImage: tab.icon)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.55)
                                .foregroundStyle(selected ? PlatinumPalette.graphite : Color.white.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
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
                ForEach(selectedPatchTab == .loadout ? DashboardPatchOption.loadout : DashboardPatchOption.visuals) { option in
                    legacyPatchButton(option)
                }
            }
            .id(selectedPatchTab)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            if selectedPatchTab == .loadout {
                Text("Aim modules share a game file, so only one aim option is active at a time.")
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [PlatinumPalette.gunmetal.opacity(0.88), AppTheme.consoleBackground.opacity(0.98), PlatinumPalette.graphite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(PlatinumPalette.silver.opacity(0.30), lineWidth: 1))
        .shadow(color: PlatinumPalette.silver.opacity(0.10), radius: 18, y: 8)
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
            Label("TRYSTORE CLASSIC CHARACTER", systemImage: "sparkles")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.82))
                .padding(10)
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.20), lineWidth: 1))
    }

    private func legacyPatchButton(_ option: DashboardPatchOption) -> some View {
        let activeTint = Color(red: 0.34, green: 0.94, blue: 0.74)
        let item = patchStore.items.first {
            $0.project?.name == option.projectName
                || (option.projectName == "TryStore" && $0.project?.name == "Balas Magicas")
                || $0.packageURL.lastPathComponent.caseInsensitiveCompare("\(option.projectName).TRYSTORE") == .orderedSame || $0.packageURL.lastPathComponent.caseInsensitiveCompare("\(option.projectName).3105") == .orderedSame
        }
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false
        let isFavorite = appState.favorites.contains(option.projectName)

        return Button {
            guard let item else { return }
            AppHaptics.tap()
            patchStore.setEnabled(!isActive, for: item, group: option.group, reportsSuccess: false, onSuccess: { enabled in PatchAudioFeedback.play(enabled: enabled) })
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(isActive ? PlatinumPalette.graphite : option.color)
                    .frame(width: 34, height: 34)
                    .background(
                        (isActive ? activeTint : option.color.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isActive {
                        Circle()
                            .fill(PlatinumPalette.graphite)
                            .frame(width: 4, height: 4)
                            .shadow(color: .white.opacity(0.8), radius: 3)
                    }
                    Text(item == nil ? "MISSING" : (isActive ? "ON" : "OFF"))
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .tracking(0.65)
                }
                .foregroundStyle(item == nil ? Color.orange : (isActive ? PlatinumPalette.graphite : Color.white.opacity(0.56)))
                .padding(.horizontal, 8)
                .frame(minWidth: 39, minHeight: 23)
                .background(
                    isActive
                        ? LinearGradient(colors: [activeTint, Color.cyan.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isActive ? Color.white.opacity(0.70) : Color.white.opacity(0.08), lineWidth: 0.8))
                .shadow(color: isActive ? activeTint.opacity(0.45) : .clear, radius: 9, y: 1)
                Image(systemName: item == nil ? "exclamationmark.triangle.fill" : (isActive ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(item == nil ? .orange : (isActive ? PlatinumPalette.silver : .white.opacity(0.30)))
                Spacer(minLength: 4)
                Button {
                    AppHaptics.tap()
                    appState.toggleFavorite(option.projectName)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.56))
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: isActive
                            ? [activeTint.opacity(0.24), Color.cyan.opacity(0.10), PlatinumPalette.silver.opacity(0.06)]
                            : [Color.white.opacity(0.065), Color.black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
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
            panelHeader(title: "FOLLOW TRYSTORE", subtitle: "OFFICIAL SOCIAL LINKS", icon: "person.2.fill")
            HStack(spacing: 9) {
                socialLinkCard(
                    title: "TikTok",
                    handle: "@vaal_goat",
                    icon: "play.rectangle.fill",
                    colors: [.black, Color(red: 0.12, green: 0.08, blue: 0.22)],
                    url: "https://www.tiktok.com/@vaal_goat"
                )
                socialLinkCard(
                    title: "Instagram",
                    handle: "@guillenrmarcos",
                    icon: "camera.fill",
                    colors: [Color(red: 0.35, green: 0.06, blue: 0.28), Color(red: 0.08, green: 0.14, blue: 0.38)],
                    url: "https://www.instagram.com/guillenrmarcos"
                )
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AppTheme.accent.opacity(0.18), lineWidth: 1))
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
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white)
                Text(handle)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.85)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.40))
            }
            Spacer()
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.57))
            Spacer(minLength: 10)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 9, design: .rounded))
    }
}

private struct HeroCornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}

private struct TryStoreAmbientBackground: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @State private var drift = false
    var touchPoint: CGPoint = .zero
    var touchStrength: Double = 0

    private var particleColors: [Color] {
        [AppTheme.accent, .cyan, .purple, .pink]
    }

    var body: some View {
        ZStack {
            // Exotic professional gradient base
            LinearGradient(
                colors: [Color(red: 0.008, green: 0.022, blue: 0.052), AppTheme.pageBackground, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Live Activity banner - shows real-time patch status
            if #available(iOS 16.1, *) {
                LiveActivityView()
                    .frame(height: 36)
            }
            // Ambient particle field - subtle and performance-friendly
            ParticleFieldView(animateDrift: $drift)
                .opacity(0.4)
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
                .fill(Color.purple.opacity(0.075))
                .frame(width: 245, height: 245)
                .blur(radius: 78)
                .offset(x: drift ? -175 : -115, y: drift ? -95 : -165)
                .scaleEffect(drift ? 1.10 : 0.88)
            Circle()
                .fill(Color.pink.opacity(0.045))
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
                            Color.purple.opacity(touchStrength * 0.18),
                            Color.pink.opacity(touchStrength * 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 205
                    )
                    .frame(width: 410, height: 410)
                    .position(touchPoint)
                    .blendMode(.screen)

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
        ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO", "BALAS", "TryStore", "Balas Magicas"]
    }

    var locationProjectNames: [String] {
        ["HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO", "ARMAS", "EXCLUSIVO AZUL"]
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
    @Environment(\.appReduceMotion) private var reduceMotion
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
        case "BALAS", "TryStore", "Balas Magicas": return "Balas Magicas"
        default: return item.project?.name ?? language.text("freefire.aim_file")
        }
    }

    private func locationDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "HOLOGRAMA EXCLUSIVO VERDE": return "EXCLUSIVO VERDE"
        case "HOLOGRAMA EXCLUSIVO ROSADO": return "EXCLUSIVO ROSADO"
        case "ARMAS", "EXCLUSIVO AZUL": return "Azul Exclusivo"
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
        let activeTint = Color(red: 0.34, green: 0.94, blue: 0.74)

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

// MARK: - PatchesView
private struct PatchesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.appReduceMotion) private var reduceMotion
    @StateObject private var patchStore = PatchProjectStore(game: .max)
    @State private var selectedPatchProjectName: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBarPatches.appCinematicReveal(delay: 0.02)
                        patchCategoriesView.appCinematicReveal(delay: 0.09)
                        activePatchesView.appCinematicReveal(delay: 0.16)
                        VStack(spacing: AppSpacing.m) {
                            AppHairline()
                            Text("TRY STORE  •  MODULE CONTROL")
                                .font(AppType.label())
                                .tracking(1.2)
                                .foregroundStyle(AppPalette.textTertiary)
                        }
                        .appCinematicReveal(delay: 0.23)
                    }
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppTheme.accent)
        }
        .task {
            guard let key = licenseManager.patchBundleKey else { return }
            patchStore.installBundledResources(bundleKey: key)
            patchStore.reload()
        }
        .alert(item: $patchStore.alert) { alert in
            let title = Text(language.text(alert.titleKey))
            let message = Text(alert.message(language: language))
            if alert.messageKey == "patch.error.pairing_tunnel_required" {
                return Alert(
                    title: title,
                    message: message,
                    primaryButton: .default(Text(language.text("settings.open_localdevvpn"))) {
                        if let url = URL(string: "localdevvpn://") { openURL(url) }
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

    private var topBarPatches: some View {
        HStack(spacing: AppSpacing.m) {
            AppLogo(size: horizontalSizeClass == .compact ? 38 : 46)
                .padding(3)
                .background(AppPalette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("PATCH STUDIO")
                    .font(.system(size: horizontalSizeClass == .compact ? 17 : 20, weight: .black, design: .rounded))
                    .tracking(horizontalSizeClass == .compact ? 1.0 : 1.5)
                    .foregroundStyle(AppPalette.textPrimary)
                Text("FREE FIRE MAX  •  MODULE CONTROL")
                    .font(AppType.label())
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
            }

            Spacer(minLength: AppSpacing.xs)

            HStack(spacing: 6) {
                Image(systemName: appState.isSupported ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appState.isSupported ? AppPalette.mint : AppPalette.amber)
                Text(appState.isSupported ? "READY" : "REVIEW")
                    .foregroundStyle(AppPalette.textPrimary)
            }
            .font(AppType.label())
            .padding(.horizontal, AppSpacing.m)
            .frame(height: 38)
            .background(AppPalette.raised.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(AppPalette.hairline.opacity(0.65), lineWidth: 1))
            .accessibilityLabel(appState.isSupported ? "Device status ready" : "Device compatibility review required")
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.panel, tint: AppTheme.accent)
    }

    private func panelHeader(title: String, subtitle: String, icon: String) -> some View {
        AppSectionHeader(icon: icon, title: title, subtitle: subtitle)
    }

    private var patchCategoriesView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            panelHeader(title: "PATCH CATEGORIES", subtitle: "CHOOSE A MODULE TYPE", icon: "square.grid.2x2.fill")
            HStack(spacing: AppSpacing.s) {
                ForEach(PatchCategory.allCases, id: \.self) { category in
                    patchCategoryButton(category)
                }
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func patchCategoryButton(_ category: PatchCategory) -> some View {
        let isSelected = selectedPatchCategory == category
        return Button {
            AppHaptics.select()
            withAnimation(reduceMotion ? nil : AppMotion.tile) {
                selectedPatchCategory = category
                selectedPatchProjectName = nil
            }
        } label: {
            ZStack {
                patchCategoryButtonBackground(isSelected: isSelected)
                Label(category.rawValue, systemImage: category.icon)
                    .font(AppType.label())
                    .tracking(0.4)
                    .foregroundStyle(isSelected ? Color(red: 0.02, green: 0.07, blue: 0.07) : AppPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(patchCategoryButtonOutline(isSelected: isSelected))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func patchCategoryButtonBackground(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(AppPalette.raised.opacity(0.55))
            if isSelected {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.mint, AppPalette.mint.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .matchedGeometryEffect(id: "patch-category-tab", in: patchTabNamespace)
                    .shadow(color: AppPalette.mint.opacity(0.32), radius: 16, y: 5)
            }
        }
    }

    private func patchCategoryButtonOutline(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            .strokeBorder(
                isSelected ? Color.white.opacity(0.30) : AppPalette.hairline.opacity(0.60),
                lineWidth: 1
            )
    }

    private var activePatchesView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            panelHeader(title: "PATCH LIBRARY", subtitle: "SELECT • ACTIVATE • RESTORE", icon: "checkmark.shield")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRYSTORE PATCHES")
                        .font(AppType.value())
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("FREE FIRE MAX  •  ORIGINAL MODULES")
                        .font(AppType.label())
                        .tracking(0.5)
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                if patchStore.isBusy {
                    ProgressView().tint(AppTheme.accent)
                }
            }

            moduleRail

            PlatinumExpiryCard(
                expirationDate: licenseManager.expirationDate,
                isActive: licenseManager.isActive
            )

            if selectedPatchCategory == .visuals { visualPatchPreview }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.s),
                    GridItem(.flexible(), spacing: AppSpacing.s)
                ],
                spacing: AppSpacing.s
            ) {
                ForEach(visiblePatchOptions) { option in
                    patchModuleCard(option)
                }
            }
            .id(selectedPatchCategory)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            if selectedPatchCategory == .loadout {
                Text("Aim modules share a game file, so only one aim option is active at a time.")
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            selectedPatchActionView
        }
        .padding(AppSpacing.l)
        .overlay(alignment: .topTrailing) {
            AppLogo(size: 148)
                .opacity(0.05)
                .offset(x: 30, y: -14)
                .allowsHitTesting(false)
        }
        .appPanel(radius: AppRadius.panel)
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
                .frame(height: 148)
                .frame(maxWidth: .infinity, alignment: .center)
                .shadow(color: AppTheme.accent.opacity(0.22), radius: 14, y: 4)
            Label("TRYSTORE CLASSIC CHARACTER", systemImage: "sparkles")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.82))
                .padding(10)
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.20), lineWidth: 1))
    }

    private func patchModuleCard(_ option: DashboardPatchOption) -> some View {
        let item = patchItem(for: option)
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false
        let isSelected = selectedPatchProjectName == option.projectName
        let isFavorite = appState.favorites.contains(option.projectName)
        let tint = isActive ? AppPalette.mint : (item == nil ? AppPalette.amber : patchTint)

        return ZStack(alignment: .topTrailing) {
            Button {
                AppHaptics.select()
                withAnimation(reduceMotion ? nil : AppMotion.tile) {
                    selectedPatchProjectName = option.projectName
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(isActive ? 0.26 : 0.12))
                            .frame(width: 58, height: 58)
                            .blur(radius: 15)
                        AppIconBadge(systemName: option.icon, tint: tint, size: 40)
                    }

                    Spacer(minLength: AppSpacing.s)

                    Text(option.title)
                        .font(AppType.body())
                        .tracking(0.2)
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.s)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .shadow(color: tint.opacity(0.9), radius: 4)
                        Text(patchRowLabel(item: item, isActive: isActive, isSelected: isSelected))
                            .font(AppType.label())
                            .tracking(0.5)
                            .foregroundStyle(isActive ? AppPalette.mint : (item == nil ? AppPalette.amber : AppPalette.textSecondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
                .padding(AppSpacing.m)
                .background(moduleCardFill(isActive: isActive, isSelected: isSelected, tint: tint))
                .overlay(moduleCardBorder(isActive: isActive, isSelected: isSelected, tint: tint))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
                .shadow(
                    color: isSelected ? tint.opacity(0.26) : Color.black.opacity(0.24),
                    radius: isSelected ? 16 : 8,
                    y: isSelected ? 6 : 4
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
            }
            .buttonStyle(AppPressButtonStyle())
            .disabled(patchStore.isBusy)
            .accessibilityLabel("Select \(option.title)")
            .accessibilityValue(patchRowAccessibilityValue(item: item, isActive: isActive, isSelected: isSelected))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                AppHaptics.tap()
                appState.toggleFavorite(option.projectName)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isFavorite ? AppPalette.amber : AppPalette.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(AppPalette.canvas.opacity(0.60), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isFavorite ? AppPalette.amber.opacity(0.40) : AppPalette.hairline.opacity(0.55), lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
        }
        .opacity(patchStore.isBusy ? 0.72 : 1)
        .animation(reduceMotion ? nil : AppMotion.tile, value: isSelected)
    }

    /// One accent per category keeps the grid readable while staying inside the
    /// TryStore palette: mint for loadout modules, blue for visual overlays.
    private var patchTint: Color {
        selectedPatchCategory == .visuals ? AppPalette.blue : AppPalette.mint
    }

    private func isPatchActive(_ option: DashboardPatchOption) -> Bool {
        guard let item = patchItem(for: option) else { return false }
        return DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    /// Full-width bus strip: eight segments, one per module, so the whole
    /// library state reads at a glance without a second list of numbers.
    private var moduleRail: some View {
        VStack(spacing: 9) {
            HStack(spacing: 3) {
                ForEach(DashboardPatchOption.all) { option in
                    Capsule()
                        .fill(isPatchActive(option) ? AppPalette.mint : AppPalette.hairline.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                        .shadow(color: isPatchActive(option) ? AppPalette.mint.opacity(0.75) : .clear, radius: 4)
                }
            }
            HStack(spacing: 6) {
                Text("MODULE BUS")
                    .font(AppType.label())
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.textTertiary)
                Spacer(minLength: AppSpacing.s)
                Text("\(activeLegacyPatchCount) / \(DashboardPatchOption.all.count) ACTIVE")
                    .font(AppType.label())
                    .tracking(0.4)
                    .foregroundStyle(AppPalette.textPrimary)
            }
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, 10)
        .background(AppPalette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.hairline.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func moduleCardFill(isActive: Bool, isSelected: Bool, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppPalette.surface.opacity(0.94), AppPalette.canvas.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(isSelected ? 0.20 : (isActive ? 0.13 : 0.05)),
                            tint.opacity(0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func moduleCardBorder(isActive: Bool, isSelected: Bool, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            .strokeBorder(
                isSelected
                    ? AnyShapeStyle(
                        AngularGradient(
                            colors: [tint, tint.opacity(0.28), Color.white.opacity(0.55), tint.opacity(0.30), tint],
                            center: .center
                        )
                    )
                    : AnyShapeStyle(AppPalette.hairline.opacity(isActive ? 0.90 : 0.55)),
                lineWidth: isSelected ? 1.6 : 1
            )
            .allowsHitTesting(false)
    }

    private func patchRowLabel(item: PatchLibraryItem?, isActive: Bool, isSelected: Bool) -> String {
        if item == nil { return "MISSING" }
        if isActive { return "ACTIVE" }
        return isSelected ? "SELECTED" : "READY"
    }

    private func patchRowAccessibilityValue(item: PatchLibraryItem?, isActive: Bool, isSelected: Bool) -> String {
        if item == nil { return "Package missing" }
        if isActive { return "Active on device" }
        return isSelected ? "Selected, ready for activation" : "Available"
    }

    private var visiblePatchOptions: [DashboardPatchOption] {
        selectedPatchCategory == .loadout ? DashboardPatchOption.loadout : DashboardPatchOption.visuals
    }

    private var selectedPatchOption: DashboardPatchOption? {
        guard let selectedPatchProjectName else { return nil }
        return visiblePatchOptions.first { $0.projectName == selectedPatchProjectName }
    }

    private var selectedPatchItem: PatchLibraryItem? {
        guard let option = selectedPatchOption else { return nil }
        return patchItem(for: option)
    }

    private var selectedPatchIsActive: Bool {
        guard let item = selectedPatchItem else { return false }
        return DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    private func patchItem(for option: DashboardPatchOption) -> PatchLibraryItem? {
        patchStore.items.first { item in
            let projectName = item.project?.name ?? ""
            let packageName = item.packageURL.lastPathComponent
            return projectName == option.projectName
                || (option.projectName == "TryStore" && projectName == "Balas Magicas")
                || packageName.caseInsensitiveCompare("\(option.projectName).TRYSTORE") == .orderedSame
                || packageName.caseInsensitiveCompare("\(option.projectName).3105") == .orderedSame
        }
    }

    private var activeLegacyPatchCount: Int {
        DashboardPatchOption.all.reduce(into: 0) { count, option in
            guard let item = patchItem(for: option),
                  DevicePatchService.latestReceipt(projectID: item.id) != nil else { return }
            count += 1
        }
    }

    private func activateSelectedPatch() {
        guard let option = selectedPatchOption, let item = selectedPatchItem else { return }
        let shouldEnable = !selectedPatchIsActive
        patchStore.setEnabled(
            shouldEnable,
            for: item,
            group: option.group,
            reportsSuccess: true,
            onSuccess: { enabled in PatchAudioFeedback.play(enabled: enabled) }
        )
    }

    private var selectedPatchActionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let option = selectedPatchOption {
                HStack(spacing: AppSpacing.m) {
                    AppIconBadge(systemName: option.icon, tint: AppTheme.accent, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SELECTED PATCH")
                            .font(AppType.label())
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.textTertiary)
                        Text(option.title)
                            .font(AppType.value())
                            .foregroundStyle(AppPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Spacer(minLength: 0)
                    if selectedPatchIsActive {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 0.34, green: 0.94, blue: 0.74))
                            .accessibilityLabel("Patch active")
                    }
                }
                if selectedPatchItem == nil {
                    Text("This patch package is missing from the library and cannot be activated.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                } else {
                    Text(selectedPatchIsActive ? "Active on device. Restore when you are finished." : "Ready to activate when you are ready.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Choose a patch above to review its status and activate it.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: activateSelectedPatch) {
                HStack(spacing: 8) {
                    if patchStore.isBusy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: selectedPatchIsActive ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    }
                    Text(selectedPatchIsActive ? "RESTORE PATCH" : "ACTIVATE PATCH")
                        .font(AppType.label())
                        .tracking(0.5)
                }
                .foregroundStyle(Color(red: 0.02, green: 0.07, blue: 0.07))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: selectedPatchIsActive
                            ? [AppPalette.amber, AppPalette.amber.opacity(0.78)]
                            : [AppPalette.mint, AppPalette.mint.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .shadow(
                    color: (selectedPatchIsActive ? AppPalette.amber : AppPalette.mint).opacity(0.30),
                    radius: 14,
                    y: 5
                )
            }
            .buttonStyle(AppPressButtonStyle())
            .disabled(selectedPatchItem == nil || patchStore.isBusy)
            .opacity(selectedPatchItem == nil || patchStore.isBusy ? 0.52 : 1)
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.tile)
    }

    // MARK: - Patch Category Enum
    private enum PatchCategory: String, CaseIterable, Identifiable {
        case loadout = "LOADOUT"
        case visuals = "VISUALS"

        var id: String { rawValue }
        var title: String { rawValue }
        var icon: String { self == .loadout ? "viewfinder" : "sparkles" }
    }

    // Navigation namespace for tab matching
    @Namespace private var patchTabNamespace
    @State private var selectedPatchCategory: PatchCategory = .loadout
}

private struct ParticleFieldView: View {
    @Binding var animateDrift: Bool
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var deviceTilt: DeviceTiltMotion
    @State private var particles: [Particle] = []

    private struct Particle: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let size: CGFloat
        let opacity: Double
        let speed: Double
        let phase: Double
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !animateDrift)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(particles) { particle in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.4), AppTheme.accent.opacity(0.2), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: particle.size, height: particle.size)
                            .position(
                                x: particleX(particle, time: time, width: geometry.size.width),
                                y: particleY(particle, time: time, height: geometry.size.height)
                            )
                            .opacity(particle.opacity)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .onAppear {
                if particles.isEmpty {
                    startParticleAnimation()
                }
            }
            .onDisappear {
                particles.removeAll()
            }
        }
    }

    private func particleX(_ particle: Particle, time: Double, width: CGFloat) -> CGFloat {
        let position = particle.x * Double(width)
            + sin(time * particle.speed + particle.phase) * 14
            + deviceTilt.roll * 8
        return CGFloat(min(max(position, 0), Double(width)))
    }

    private func particleY(_ particle: Particle, time: Double, height: CGFloat) -> CGFloat {
        let position = particle.y * Double(height)
            + cos(time * particle.speed * 0.8 + particle.phase) * 14
            - deviceTilt.pitch * 8
        return CGFloat(min(max(position, 0), Double(height)))
    }

    private func startParticleAnimation() {
        particles = (0..<12).map { index in
            Particle(
                id: index,
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: CGFloat.random(in: 1...4),
                opacity: 0.3 + Double(index) * 0.04,
                speed: Double.random(in: 0.2...0.8),
                phase: Double.random(in: 0...(Double.pi * 2))
            )
        }
    }
}

@available(iOS 16.1, *)
struct LiveActivityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activity: Activity<LiveActivityState>?

    var body: some View {
        Group {
            if let activity = activity {
                LiveActivityBanner(activity: activity) {
                    await updateLiveActivity()
                }
            } else {
                Button("Start Live Activity") {
                    Task {
                        await startLiveActivity()
                    }
                }
                .buttonStyle(.plain)
                .disabled(!ActivityAuthorizationInfo().areActivitiesEnabled)
            }
        }
        .task {
            activity = Activity<LiveActivityState>.activities.first
        }
    }

    private func startLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let initialState = LiveActivityState.ContentState(
            isActive: true,
            cpuTemp: nil,
            gpuTemp: nil,
            thermalState: appState.thermalStateLabel,
            launchCount: appState.totalLaunches
        )

        do {
            activity = try Activity<LiveActivityState>.request(
                attributes: LiveActivityState(),
                contentState: initialState,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    private func updateLiveActivity() async {
        guard let activity = activity else { return }
        let updatedState = LiveActivityState.ContentState(
            isActive: true,
            cpuTemp: nil,
            gpuTemp: nil,
            thermalState: appState.thermalStateLabel,
            launchCount: appState.totalLaunches
        )
        await activity.update(using: updatedState)
    }
}

@available(iOS 16.1, *)
struct LiveActivityBanner: View {
    let activity: Activity<LiveActivityState>
    let onRefresh: () async -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Patch Activity")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                
                Label("SYSTEM THERMAL", systemImage: "thermometer.medium")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.orange)
                Text(activity.contentState.thermalState ?? "Unknown")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer(minLength: 4)
            
            Button {
                Task { await onRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
