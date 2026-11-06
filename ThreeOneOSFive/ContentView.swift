import SwiftUI
import ActivityKit
import UIKit
import AVFoundation

@available(iOS 16.1, *)
struct LiveActivityState: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let isActive: Bool
        let cpuTemp: Double?
        let gpuTemp: Double?
        let thermalState: String?
        let launchCount: Int
        /// 0...1 while an operation runs. Surfaced so the Live Activity can show
        /// the same number the in-app card does.
        let progress: Double
        /// What is running: "ACTIVATING", "RESTORING", "Cleaner".
        let operation: String?
    }
}

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var patchStore = PatchProjectStore(game: .max)
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onOpenPatches: { selectedTab = 1 })
                .tabItem {
                    Label(language.text("tab.home"), systemImage: "house.fill")
                }
                .tag(0)
            PatchesView()
                .tabItem {
                    Label(language.text("tab.patches"), systemImage: "square.grid.2x2")
                }
                .tag(1)
            CleanerView()
                .tabItem {
                    Label(language.text("tab.clean"), systemImage: "sparkles")
                }
                .tag(2)
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .appSelectionFeedback(trigger: selectedTab)
        .environmentObject(patchStore)
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
    @EnvironmentObject private var patchStore: PatchProjectStore
    @StateObject private var pairingController = PairingController()
    @State private var isPairingReady = false
    @State private var isTunnelConnected: Bool?
    @State private var isPairingImporterPresented = false
    @State private var isPairingImporting = false
    @State private var isPairingDeleteConfirmationPresented = false
    @State private var pairingImportErrorKey: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBarHome.appCinematicReveal(delay: 0.02)
                        heroHome.appCinematicReveal(delay: 0.08)
                        vitalPanelHome.appCinematicReveal(delay: 0.15)
                        moduleStatusPanelHome.appCinematicReveal(delay: 0.19)
                        connectionPanelHome.appCinematicReveal(delay: 0.21)
                        quickAccessHome.appCinematicReveal(delay: 0.24)
                        deviceSectionHome.appCinematicReveal(delay: 0.27)
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
        .sheet(isPresented: $isPairingImporterPresented) {
            PairingDocumentPicker { url in
                isPairingImporterPresented = false
                importPairing(from: url)
            }
        }
        .confirmationDialog(
            language.text("settings.delete_pairing_confirm_title"),
            isPresented: $isPairingDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(language.text("settings.delete_pairing"), role: .destructive) {
                do {
                    try PairingFileStore.delete()
                    isPairingReady = false
                } catch {
                    pairingImportErrorKey = "settings.delete_pairing_failed"
                }
            }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("settings.delete_pairing_confirm_message"))
        }
        .alert(
            language.text(pairingErrorTitleKey),
            isPresented: Binding(
                get: { pairingImportErrorKey != nil },
                set: { if !$0 { pairingImportErrorKey = nil } }
            )
        ) {
            Button(language.text("common.ok"), role: .cancel) {
                pairingImportErrorKey = nil
            }
        } message: {
            Text(language.text(pairingImportErrorKey ?? "settings.pairing_import_failed"))
        }
        .onAppear { isPairingReady = PairingFileStore.isReady }
        .onReceive(pairingController.$status) { status in
            if status == "Pairing ready" {
                isPairingReady = PairingFileStore.isReady
            }
        }
        .task {
            patchStore.installBundledResources()
            patchStore.reload()
        }
        .task {
            while !Task.isCancelled {
                isTunnelConnected = LocalDevTunnelProbe.isConnected
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - Header

    private var topBarHome: some View {
        HStack(spacing: AppSpacing.m) {
            AppLogo(size: horizontalSizeClass == .compact ? 38 : 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("TRY STORE")
                    .font(.system(size: horizontalSizeClass == .compact ? 19 : 21, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text("MAX CONTROL  /  VISUAL LAB")
                    .font(AppType.label())
                    .foregroundStyle(AppPalette.textTertiary)
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
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppPalette.surface, in: Circle())
                .overlay(Circle().strokeBorder(AppPalette.hairline.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Hero

    /// The stage carries no copy: the figure is the whole point of the panel, and
    /// the captions that used to sit on it pushed the modules further down the
    /// screen. It is decorative, so VoiceOver skips it and the content below
    /// starts sooner.
    private var heroHome: some View {
        BrandCharacterBackdrop(reduceMotion: reduceMotion)
            .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 340)
            .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Module control

    private func patchItemHome(for option: DashboardPatchOption) -> PatchLibraryItem? {
        option.resolve(in: patchStore.items)
    }

    private func isModuleActiveHome(_ option: DashboardPatchOption) -> Bool {
        guard let item = patchItemHome(for: option) else { return false }
        return DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    private var activeModuleCountHome: Int {
        DashboardPatchOption.unique.reduce(into: 0) { count, option in
            if isModuleActiveHome(option) { count += 1 }
        }
    }

    /// The patch store lives in the Patches tab, so Home reads the same receipts
    /// the device already carries rather than keeping a second copy of the state.
    private var moduleStatusPanelHome: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(
                icon: "square.grid.2x2.fill",
                title: language.text("home.modules.title"),
                subtitle: language.text("home.modules.subtitle")
            )

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(activeModuleCountHome)")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
                Text("/ \(DashboardPatchOption.unique.count)")
                    .font(AppType.value())
                    .foregroundStyle(AppPalette.textTertiary)
                    .monospacedDigit()
                Spacer(minLength: AppSpacing.s)
                AppStatChip(
                    icon: activeModuleCountHome > 0 ? "checkmark.seal.fill" : "circle.dashed",
                    text: language.text(activeModuleCountHome > 0 ? "home.modules.patched" : "home.modules.clean"),
                    tint: activeModuleCountHome > 0 ? AppPalette.mint : AppPalette.textTertiary
                )
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 3) {
                ForEach(DashboardPatchOption.unique) { option in
                    Capsule()
                        .fill(isModuleActiveHome(option) ? AppPalette.brand : AppPalette.hairline.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)

            Text(language.text("home.modules.caption"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            AppActionButton(title: language.text("home.modules.open"), icon: "arrow.up.right") {
                onOpenPatches()
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
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
                        tint: AppPalette.brand
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
                .font(.system(size: 12, weight: .regular))
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

    // MARK: - Connections

    private var tunnelConnected: Bool {
        isTunnelConnected == true
    }

    private var tunnelStatusKeyHome: String {
        guard let isTunnelConnected else { return "settings.tunnel_checking" }
        return isTunnelConnected ? "settings.tunnel_connected" : "settings.tunnel_disconnected"
    }

    private var pairingErrorTitleKey: String {
        pairingImportErrorKey == "settings.delete_pairing_failed"
            ? "settings.delete_pairing_error_title"
            : "settings.pairing_import_error_title"
    }

    private var connectActionTitleKey: String {
        if pairingController.isRunning { return "settings.stop_pairing" }
        return tunnelConnected ? "settings.pair_on_this_iphone" : "settings.open_localdevvpn"
    }

    private var connectActionIcon: String {
        if pairingController.isRunning { return "stop.circle.fill" }
        return tunnelConnected ? "iphone.gen3" : "network"
    }

    /// Airlift and the tunnel used to live in Settings. They are the two links
    /// every patch funnels through, so their state belongs on the Home surface.
    private var connectionPanelHome: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(
                icon: "antenna.radiowaves.left.and.right",
                title: language.text("home.shortcut.connections"),
                subtitle: language.text("home.shortcut.connections_detail"),
                tint: tunnelConnected ? AppPalette.mint : AppTheme.accent
            )

            VStack(spacing: AppSpacing.s) {
                connectionRow(
                    icon: "iphone.gen3",
                    title: language.text("settings.pairing"),
                    value: language.text(isPairingReady ? "settings.pairing_ready" : "settings.pairing_missing"),
                    tint: isPairingReady ? AppPalette.mint : AppPalette.amber
                )
                connectionRow(
                    icon: "network",
                    title: language.text("settings.tunnel"),
                    value: language.text(tunnelStatusKeyHome),
                    tint: tunnelConnected ? AppPalette.mint : AppPalette.textTertiary
                )
            }

            if AppInfo.versionTuple.major >= 27 || DevicePatchService.requiresPairingTunnel {
                AppActionButton(
                    title: language.text(connectActionTitleKey),
                    icon: connectActionIcon,
                    tint: tunnelConnected ? AppPalette.mint : AppTheme.accent
                ) {
                    handleConnectAction()
                }
            }

            if let pin = pairingController.pin {
                Text(language.text("settings.pairing_pin", pin))
                    .font(AppType.value())
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }

            if pairingController.isRunning {
                Text(pairingController.status)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = pairingController.errorMessage {
                Text(error)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(language.text("settings.pairing_direct_note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.s) {
                AppActionButton(
                    title: language.text("settings.import_pairing"),
                    icon: "square.and.arrow.down",
                    tint: AppTheme.accentSecondary,
                    isProminent: false,
                    isEnabled: !isPairingImporting
                ) {
                    isPairingImporterPresented = true
                }

                if isPairingReady {
                    AppActionButton(
                        title: language.text("settings.delete_pairing"),
                        icon: "trash",
                        tint: AppPalette.coral,
                        isProminent: false
                    ) {
                        isPairingDeleteConfirmationPresented = true
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel, tint: tunnelConnected ? AppPalette.brand : AppTheme.accent)
    }

    private func connectionRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.m) {
            AppIconBadge(systemName: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                Text(value)
                    .font(AppType.label())
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private func handleConnectAction() {
        AppHaptics.tap()
        if pairingController.isRunning {
            pairingController.cancel()
        } else if tunnelConnected {
            pairingController.start(
                pinNotificationTitle: language.text("settings.pairing_pin_notification_title"),
                pinNotificationBodyFormat: language.text("settings.pairing_pin_notification_body")
            )
        } else {
            openLocalDevVPN()
        }
    }

    private func openLocalDevVPN() {
        let appURL = URL(string: "localdevvpn://")!
        let appStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!
        UIApplication.shared.open(appURL) { opened in
            if !opened {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }

    private func importPairing(from url: URL) {
        isPairingImporting = true
        pairingImportErrorKey = nil
        Task { @MainActor in
            do {
                let isReady = try await Task.detached(priority: .userInitiated) {
                    try PairingFileStore.importFile(from: url)
                    return PairingFileStore.isReady
                }.value
                isPairingReady = isReady
                isPairingImporting = false
            } catch PairingFileImportError.invalidPropertyList {
                pairingImportErrorKey = "settings.pairing_import_invalid"
                isPairingImporting = false
            } catch PairingFileImportError.fileTooLarge {
                pairingImportErrorKey = "settings.pairing_import_too_large"
                isPairingImporting = false
            } catch {
                pairingImportErrorKey = "settings.pairing_import_failed"
                isPairingImporting = false
            }
        }
    }

    // MARK: - Quick access

    private var quickAccessHome: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppSpacing.m),
                GridItem(.flexible(), spacing: AppSpacing.m)
            ],
            spacing: AppSpacing.m
        ) {
            quickAccessCardHome(
                icon: "square.grid.2x2",
                title: language.text("home.shortcut.patches"),
                detail: language.text("home.shortcut.patches_detail")
            ) {
                onOpenPatches()
            }
            .accessibilityLabel(language.text("home.shortcut.patches"))

            quickAccessCardHome(
                icon: "apple.terminal",
                title: language.text("home.shortcut.logs"),
                detail: language.text("home.shortcut.logs_detail")
            ) {
                showLogs = true
            }
            .accessibilityLabel(language.text("accessibility.open_logs"))

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

/// Home hero stage. The rotating character, the TryStore emblem and the accent
/// ring are baked into `CharacterHeroLoop.mp4` at the hero's own square shape, so the
/// backdrop is one element instead of a stack of overlays. The loop is silent and
/// pauses with the scene; Reduce Motion and a failed load keep the still frame.
private struct BrandCharacterBackdrop: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let reduceMotion: Bool

    @StateObject private var heroPlayer = CharacterHeroPlayer()
    @State private var isVisible = false

    /// Phones take the stage to the panel edges. Wide layouts keep the whole
    /// stage visible instead of cropping the hat and the heels.
    private var fillsStage: Bool { horizontalSizeClass == .compact }

    /// Reduce Motion keeps the still frame, and the loop only runs while the hero
    /// is on screen in the foreground.
    private var shouldPlay: Bool {
        !reduceMotion && scenePhase == .active && isVisible
    }

    /// The video only covers the poster once it is genuinely running, so a player
    /// that never starts shows frame zero rather than a frozen layer.
    private var showsLoop: Bool { shouldPlay && heroPlayer.isRunning }

    var body: some View {
        ZStack {
            AppPalette.canvas

            Image("CharacterHeroStage")
                .resizable()
                .aspectRatio(contentMode: fillsStage ? .fill : .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsLoop ? 0 : 1)
                .accessibilityHidden(true)

            if heroPlayer.hasLoop {
                VideoPlayerSurface(player: heroPlayer.player, fillsStage: fillsStage)
                    .opacity(showsLoop ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .task(id: shouldPlay) {
            if shouldPlay {
                heroPlayer.start()
            } else {
                heroPlayer.stop()
            }
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            heroPlayer.stop()
        }
    }
}

/// Owns the hero loop. `AVPlayer.play()` is ignored while an item is still
/// loading, and an item always loads asynchronously, so playback waits for the
/// ready status instead of trusting the call made while the player was built.
@MainActor
private final class CharacterHeroPlayer: ObservableObject {
    @Published private(set) var isRunning = false
    let player: AVQueuePlayer
    let hasLoop: Bool

    private var looper: AVPlayerLooper?
    private var startTask: Task<Void, Never>?

    /// An item reports ready a few hundred milliseconds after the player is
    /// built. Both waits are bounded, so a clip that never loads settles on the
    /// still frame instead of retrying for the life of the screen.
    private static let readinessChecks = 40
    private static let readinessInterval: UInt64 = 100_000_000
    private static let playbackProbe: UInt64 = 250_000_000
    private static let playbackProbes = 3

    init() {
        let queuePlayer = AVQueuePlayer()
        player = queuePlayer

        guard let url = Bundle.main.url(forResource: "CharacterHeroLoop", withExtension: "mp4") else {
            hasLoop = false
            log("hero: CharacterHeroLoop.mp4 missing from the bundle, keeping the still frame")
            return
        }

        hasLoop = true
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .advance
        // A local file has nothing to buffer, and an ambient loop must not hold
        // the display awake the way a watched video does.
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
    }

    func start() {
        guard hasLoop, startTask == nil else { return }
        startTask = Task { [weak self] in
            await self?.runUntilPlaying()
            self?.startTask = nil
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        isRunning = false
        player.pause()
        player.seek(to: .zero)
    }

    /// Waits for the item to load, then starts it and confirms the state actually
    /// changed. `isRunning` is only set once the player reports it is playing, so
    /// a start that is silently dropped leaves the still frame on screen rather
    /// than a frozen video the user reads as a broken hero.
    private func runUntilPlaying() async {
        for _ in 0..<Self.readinessChecks {
            if Task.isCancelled { return }
            guard player.currentItem?.status == .readyToPlay else {
                try? await Task.sleep(nanoseconds: Self.readinessInterval)
                continue
            }
            for probe in 0..<Self.playbackProbes {
                if Task.isCancelled { return }
                player.playImmediately(atRate: 1)
                try? await Task.sleep(nanoseconds: Self.playbackProbe)
                if player.timeControlStatus == .playing {
                    isRunning = true
                    log("hero: loop playing")
                    return
                }
                log("hero: loop start attempt \(probe + 1) did not take")
            }
            log("hero: loop reported ready but stayed paused, keeping the still frame")
            return
        }
        log("hero: loop never reported ready, keeping the still frame")
    }
}

private struct VideoPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let fillsStage: Bool

    func makeUIView(context: Context) -> VideoPlayerSurfaceView {
        let view = VideoPlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: VideoPlayerSurfaceView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        if view.playerLayer.videoGravity != gravity {
            view.playerLayer.videoGravity = gravity
        }
    }

    private var gravity: AVLayerVideoGravity {
        fillsStage ? .resizeAspectFill : .resizeAspect
    }
}

private final class VideoPlayerSurfaceView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
    }
}


// MARK: - PatchesView
private enum DashboardPatchTab: String, CaseIterable, Identifiable {
    case loadout
    case visuals
    case antena

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .loadout: return "patch.mode.loadout"
        case .visuals: return "patch.mode.visuals"
        case .antena: return "patch.mode.antena"
        }
    }
    var icon: String {
        switch self {
        case .loadout: return "scope"
        case .visuals: return "sparkles"
        case .antena: return "antenna.radiowaves.left.and.right"
        }
    }
}

private struct PatchCategoryNotice: View {
    let title: String
    let detail: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppType.label())
                    .foregroundStyle(tint)
                Text(detail)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous).stroke(tint.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Legacy "platinum" tones, retuned to the shared palette so the older panels
/// and pills read as part of the same surface family instead of a second theme.
private enum PlatinumPalette {
    static let bright = AppPalette.textPrimary
}

private struct PlatinumExpiryCard: View {
    let expirationDate: Date?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Circle()
                    .trim(from: 0.04, to: 0.76)
                    .stroke(AppPalette.brand, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Image(systemName: expirationDate == nil ? "key.fill" : "hourglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PlatinumPalette.bright)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LICENSE WINDOW")
                        .font(AppType.label())
                        .foregroundStyle(PlatinumPalette.bright)
                    Spacer(minLength: 4)
                    Text(isActive ? "AUTHORIZED" : "VERIFYING")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? AppPalette.brand : AppPalette.textTertiary)
                }

                if let expirationDate {
                    Text(expiryStamp(expirationDate))
                        .font(AppType.body())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(countdown(to: expirationDate, now: context.date))
                            .font(AppType.digits(10))
                            .foregroundStyle(AppPalette.textSecondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("NO EXPIRY TIMESTAMP PROVIDED")
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("The license service did not return an expiry date.")
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.m)
        .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
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
    let packageID: UUID?

    init(
        projectName: String,
        title: String,
        icon: String,
        color: Color,
        group: PatchToggleGroup?,
        packageID: UUID? = nil
    ) {
        self.projectName = projectName
        self.title = title
        self.icon = icon
        self.color = color
        self.group = group
        self.packageID = packageID
    }

    var id: String {
        if projectName == "TryStore" { return projectName }
        return packageID?.uuidString ?? projectName
    }

    func resolve(in items: [PatchLibraryItem]) -> PatchLibraryItem? {
        if let packageID {
            let matches = items.filter { $0.id == packageID }
            return matches.count == 1 ? matches.first : nil
        }
        let matches = items.filter { item in
            if let internalName = item.project?.name {
                return PatchProjectLibrary.projectNameMatches(
                    expected: projectName,
                    actual: internalName
                )
            }
            let filename = item.packageURL.deletingPathExtension().lastPathComponent
            return PatchProjectLibrary.projectNameMatches(
                expected: projectName,
                actual: filename
            )
        }
        return matches.count == 1 ? matches.first : nil
    }

    static let loadout = [
        DashboardPatchOption(projectName: "HEAD", title: "HEAD", icon: "viewfinder", color: .indigo, group: .aim, packageID: UUID(uuidString: "668D6990-D407-439F-8846-2AC6E03498BA")!),
        DashboardPatchOption(projectName: "NECK", title: "NECK", icon: "scope", color: .cyan, group: .aim, packageID: UUID(uuidString: "74028F92-DE35-43F0-8E40-423D10EE3D42")!),
        DashboardPatchOption(projectName: "HS PESSCOSO", title: "DRAG", icon: "arrow.up.right.and.arrow.down.left", color: .orange, group: .aim, packageID: UUID(uuidString: "6E3DE2CA-1F8D-435F-A366-7692994D0094")!),
        DashboardPatchOption(projectName: "HS SLA PECHO", title: "PECHO", icon: "scope", color: AppTheme.accent, group: .aim, packageID: UUID(uuidString: "6A510E8A-A467-48D3-B81D-7B6E482FEFCB")!)
    ]

    static let visuals = [
        DashboardPatchOption(projectName: "HOLOGRAMA EXCLUSIVO VERDE", title: "EXCLUSIVO VERDE", icon: "leaf.fill", color: .green, group: nil, packageID: UUID(uuidString: "B1672AC3-AE42-4A0A-9A11-02A54C2C8F10")!),
        DashboardPatchOption(projectName: "HOLOGRAMA EXCLUSIVO ROSADO", title: "EXCLUSIVO ROSADO", icon: "heart.fill", color: .pink, group: nil, packageID: UUID(uuidString: "2E5D8A71-3C4B-4F92-8D6A-7715C8E34B20")!),
        DashboardPatchOption(projectName: "EXCLUSIVO AZUL", title: "Azul Exclusivo", icon: "flame.fill", color: .blue, group: nil, packageID: UUID(uuidString: "1B7B4E1F-027B-4747-A933-2F545DC19DE2")!)
    ]

    static let antena = [
        DashboardPatchOption(projectName: "Balas Magicas", title: "Balas Magicas", icon: "sparkles", color: .yellow, group: .antena, packageID: UUID(uuidString: "42CE925C-05DF-4D95-8DE0-E229BE02E599")!),
        DashboardPatchOption(projectName: "Drag con Cuello", title: "Cuello y Drag", icon: "scope", color: .cyan, group: .antena, packageID: UUID(uuidString: "730F4929-EAF2-47D8-8EC1-39210322E46F")!),
        DashboardPatchOption(projectName: "Aimbot Pecho", title: "Pecho3105", icon: "scope", color: .orange, group: .antena, packageID: UUID(uuidString: "68F2ACB2-2464-4CC3-ABFA-30D29077A81B")!),
        DashboardPatchOption(projectName: "Aimbot Pecho", title: "CUELLO3105", icon: "scope", color: .pink, group: .antena, packageID: UUID(uuidString: "0F13736C-D7A2-4E02-AC21-40DFC8463F89")!)
    ]

    static var all: [DashboardPatchOption] { loadout + visuals + antena }

    static var unique: [DashboardPatchOption] {
        var seenPackages = Set<UUID>()
        var seenNames = Set<String>()
        return all.filter { option in
            if let packageID = option.packageID {
                return seenPackages.insert(packageID).inserted
            }
            return seenNames.insert(option.projectName).inserted
        }
    }

    static func options(for tab: DashboardPatchTab) -> [DashboardPatchOption] {
        switch tab {
        case .loadout: return loadout
        case .visuals: return visuals
        case .antena: return antena
        }
    }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var patchStore: PatchProjectStore
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
                        topBar.appCinematicReveal(delay: 0.02).appDepthLayer(.card)
                        heroPanel.appCinematicReveal(delay: 0.08).appDepthLayer(.hero)
                        telemetryStrip.appCinematicReveal(delay: 0.15).appDepthLayer(.card)
                        legacyPatchPanel.appCinematicReveal(delay: 0.22).appDepthLayer(.card)
                        deviceSection.appCinematicReveal(delay: 0.29).appDepthLayer(.card)
                        quickStartPanel.appCinematicReveal(delay: 0.36).appDepthLayer(.card)
                        characterPreviewPanel.appCinematicReveal(delay: 0.43).appDepthLayer(.hero)
                        socialLinksPanel.appCinematicReveal(delay: 0.50).appDepthLayer(.card)
                        footerBar.appCinematicReveal(delay: 0.56).appDepthLayer(.card)
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
            patchStore.installBundledResources()
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

    private func deviceMetricCardHome(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
        .padding(10)
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
                    Text("\(activeLegacyPatchCount) / \(DashboardPatchOption.unique.count) ACTIVE")
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
                                Capsule()
                                    .fill(AppPalette.raised)
                                    .matchedGeometryEffect(id: "platinum-patch-tab", in: patchTabNamespace)
                            }
                            Label(language.text(tab.titleKey), systemImage: tab.icon)
                                .font(AppType.label())
                                .foregroundStyle(selected ? AppPalette.brand : AppPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(selected ? AppPalette.brand : AppPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            dashboardPatchNotice

            if selectedPatchTab == .visuals {
                visualPatchPreview
            }

            VStack(spacing: 7) {
                ForEach(DashboardPatchOption.options(for: selectedPatchTab)) { option in
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
        .padding(AppSpacing.l)
        .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                patchSheen = true
            }
        }
    }

    private var dashboardPatchNotice: some View {
        switch selectedPatchTab {
        case .loadout:
            PatchCategoryNotice(
                title: language.text("patch.safety.aim_label"),
                detail: language.text("patch.safety.aim_detail"),
                tint: AppPalette.mint,
                icon: "checkmark.shield.fill"
            )
        case .visuals:
            PatchCategoryNotice(
                title: language.text("patch.safety.visuals_label"),
                detail: language.text("patch.safety.visuals_detail"),
                tint: AppPalette.amber,
                icon: "exclamationmark.triangle.fill"
            )
        case .antena:
            PatchCategoryNotice(
                title: language.text("patch.safety.antena_label"),
                detail: language.text("patch.safety.antena_detail"),
                tint: AppTheme.accent,
                icon: "antenna.radiowaves.left.and.right"
            )
        }
    }

    private var visualPatchPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(AppPalette.canvas)
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(height: 132)
                .frame(maxWidth: .infinity, alignment: .center)
            Label("TRYSTORE CLASSIC CHARACTER", systemImage: "sparkles")
                .font(AppType.label())
                .foregroundStyle(AppPalette.textPrimary)
                .padding(10)
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
    }

    private func dashboardPatchItem(for option: DashboardPatchOption) -> PatchLibraryItem? {
        option.resolve(in: patchStore.items)
    }

    private func legacyPatchButton(_ option: DashboardPatchOption) -> some View {
        let activeTint = AppPalette.brand
        let item = dashboardPatchItem(for: option)
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false
        let isFavorite = appState.favorites.contains(option.id)

        return Button {
            guard let item else { return }
            AppHaptics.tap()
            patchStore.setEnabled(!isActive, for: item, group: option.group, reportsSuccess: false, onSuccess: { enabled in PatchAudioFeedback.play(enabled: enabled) })
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isActive ? activeTint : AppPalette.textSecondary)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(item == nil ? "MISSING" : (isActive ? "ON" : "OFF"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(item == nil ? AppPalette.amber : (isActive ? activeTint : AppPalette.textSecondary))
                .padding(.horizontal, 8)
                .frame(minWidth: 39, minHeight: 23)
                Image(systemName: item == nil ? "exclamationmark.triangle.fill" : (isActive ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(item == nil ? AppPalette.amber : (isActive ? activeTint : AppPalette.textTertiary))
                Spacer(minLength: 4)
                Button {
                    AppHaptics.tap()
                    appState.toggleFavorite(option.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isFavorite ? AppPalette.brand : AppPalette.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background(isActive ? activeTint.opacity(0.10) : AppPalette.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                    .strokeBorder(isActive ? activeTint : AppPalette.hairline.opacity(0.6), lineWidth: 1)
            )
            .animation(reduceMotion ? nil : AppMotion.tile, value: isActive)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
        }
        .disabled(patchStore.isBusy || item == nil)
        .opacity(patchStore.isBusy ? 0.72 : (item == nil ? 0.52 : 1))
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel("\(option.title), \(isActive ? "on" : "off")")
    }

    private var activeLegacyPatchCount: Int {
        DashboardPatchOption.unique.reduce(into: 0) { count, option in
            guard let item = dashboardPatchItem(for: option),
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
            .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
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
                    .foregroundStyle(isActive ? AppPalette.canvas : AppPalette.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 20)
                    .background(isActive ? activeTint : AppPalette.raised, in: Capsule())
            }
        }
        .tint(isActive ? activeTint : AppTheme.accent)
        .padding(AppSpacing.m)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .strokeBorder(isActive ? activeTint : AppPalette.hairline.opacity(0.6), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : AppMotion.tile, value: isActive)
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
                                    .appDepthLayer(.card)
                            }
                        } else {
                            if locationItems.isEmpty {
                                emptyPatchNotice
                            }
                            ForEach(locationItems) { item in
                                patchToggleCard(item, title: locationDisplayName(for: item), icon: "location.fill", group: .location)
                                    .appCinematicReveal(delay: 0.22)
                                    .appDepthLayer(.card)
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
        isLoading = true
        loadError = nil
        store.installBundledResources()
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
// MARK: - Patch module card

/// One module. The featured variant leads the deck; the rest sit in a two-column
/// grid. Selection and active state are indicated by a quiet edge and a clear label.
private struct PatchModuleCardView: View {
    let title: String
    let icon: String
    let status: String
    let tint: Color
    let indexLabel: String
    let isActive: Bool
    let isSelected: Bool
    let isFavorite: Bool
    let isBusy: Bool
    let isFeatured: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                content
                    .frame(maxWidth: .infinity, minHeight: isFeatured ? 92 : 138, alignment: .leading)
                    .padding(isFeatured ? AppSpacing.m : 13)
                    .background(fill)
                    .overlay(border)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
            }
            .buttonStyle(AppPressButtonStyle())
            .disabled(isBusy)
            .accessibilityLabel("Select \(title)")
            .accessibilityValue(isActive ? "Active on device" : (isSelected ? "Selected, ready for activation" : "Available"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: onToggleFavorite) {
                starGlyph
            }
            .buttonStyle(AppPressButtonStyle())
            .padding(.top, isFeatured ? 8 : 6)
            .padding(.trailing, 6)
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
        }
        .opacity(isBusy ? 0.72 : 1)
        .animation(reduceMotion ? nil : AppMotion.tile, value: isSelected)
    }

    @ViewBuilder
    private var content: some View {
        if isFeatured {
            HStack(spacing: AppSpacing.m) {
                badge(size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    statusRow
                }
                Spacer(minLength: AppSpacing.s)
                Text(indexLabel)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppPalette.textTertiary)
                    .padding(.trailing, 2)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                badge(size: 42)
                Spacer(minLength: AppSpacing.m)
                Text(title)
                    .font(AppType.body())
                    .tracking(0.2)
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 7)
                HStack(spacing: 6) {
                    statusRow
                    Spacer(minLength: 0)
                    Text(indexLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func badge(size: CGFloat) -> some View {
        AppIconBadge(systemName: icon, tint: tint, size: size)
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? AppPalette.brand : AppPalette.hairline)
                .frame(width: 5, height: 5)
            Text(status)
                .font(AppType.label())
                .tracking(0.5)
                .foregroundStyle(isActive ? AppPalette.brand : AppPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
    }

    private var starGlyph: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(isFavorite ? AppPalette.brand : AppPalette.textTertiary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var fill: some View {
        RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            .fill(isSelected ? AppPalette.raised : AppPalette.canvas)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            .strokeBorder(isSelected ? AppPalette.brand : AppPalette.hairline.opacity(0.35), lineWidth: 1)
            .allowsHitTesting(false)
    }
}

private struct PatchesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.appReduceMotion) private var reduceMotion
    @EnvironmentObject private var patchStore: PatchProjectStore
    @State private var selectedPatchProjectName: String?
    @State private var patchProgress: Double = 0
    @State private var patchProgressStage = ""
    @State private var patchProgressSub = ""
    @State private var showPatchProgress = false
    @State private var patchProgressTask: Task<Void, Never>?
    @State private var patchOperationIsEnabling = true
    @State private var patchOperationFinished = false
    @State private var patchOperationSucceeded = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBarPatches.appCinematicReveal(delay: 0.02)
                        patchCategoriesView.appCinematicReveal(delay: 0.09)
                        activePatchesView.appCinematicReveal(delay: 0.16)
                    }
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }

                if showPatchProgress {
                    patchProgressOverlay
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .onChange(of: patchStore.isBusy) { isBusy in
                guard !isBusy, showPatchProgress, !patchOperationFinished else { return }
                if let option = selectedPatchOption, let item = patchItem(for: option) {
                    let isActive = DevicePatchService.latestReceipt(projectID: item.id) != nil
                    patchOperationSucceeded = isActive == patchOperationIsEnabling
                }
                finishPatchProgress()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppTheme.accent)
        }
        .task {
            patchStore.installBundledResources()
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
            VStack(alignment: .leading, spacing: 2) {
                Text("PATCH STUDIO")
                    .font(.system(size: horizontalSizeClass == .compact ? 19 : 21, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text("FREE FIRE MAX  •  MODULE CONTROL")
                    .font(AppType.label())
                    .foregroundStyle(AppPalette.textTertiary)
            }

            Spacer(minLength: AppSpacing.xs)

            HStack(spacing: 6) {
                Image(systemName: appState.isSupported ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appState.isSupported ? AppPalette.mint : AppPalette.amber)
                Text(appState.isSupported ? language.text("patch.status.ready") : language.text("patch.status.review"))
                    .foregroundStyle(AppPalette.textPrimary)
            }
            .font(AppType.label())
            .padding(.horizontal, AppSpacing.m)
            .frame(height: 38)
            .background(AppPalette.raised, in: Capsule())
            .accessibilityLabel(appState.isSupported ? language.text("patch.compat.ready") : language.text("patch.compat.review"))
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.panel, tint: AppTheme.accent)
    }

    private func panelHeader(title: String, subtitle: String, icon: String) -> some View {
        AppSectionHeader(icon: icon, title: title, subtitle: subtitle)
    }

    private var patchCategoriesView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                panelHeader(title: language.text("patch.categories"), subtitle: language.text("patch.categories.subtitle"), icon: "square.grid.2x2.fill")
                Spacer(minLength: 0)
            }
            HStack(spacing: AppSpacing.s) {
                ForEach(PatchCategory.allCases, id: \.self) { category in
                    patchCategoryButton(category)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
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
                Label(language.text(category.titleKey), systemImage: category.icon)
                    .font(AppType.label())
                    .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .clipShape(Capsule())
            .overlay(patchCategoryButtonOutline(isSelected: isSelected))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func patchCategoryButtonBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? AppPalette.raised : Color.clear)
    }

    private func patchCategoryButtonOutline(isSelected: Bool) -> some View {
        Capsule()
            .strokeBorder(isSelected ? AppPalette.brand : AppPalette.hairline.opacity(0.45), lineWidth: 1)
    }

    private var activePatchesView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            panelHeader(title: language.text("patch.library"), subtitle: language.text("patch.library.subtitle"), icon: "checkmark.shield")
            patchConsole
            patchStudioCategoryNotice

            PlatinumExpiryCard(
                expirationDate: licenseManager.expirationDate,
                isActive: licenseManager.isActive
            )

            if selectedPatchCategory == .visuals { visualPatchPreview }

            VStack(spacing: AppSpacing.m) {
                if let featured = visiblePatchOptions.first {
                    patchModuleCard(featured, index: 1, isFeatured: true)
                }
                HStack(spacing: AppSpacing.s) {
                    Text(language.text("patch.other_modules"))
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textTertiary)
                    AppHairline()
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.s),
                        GridItem(.flexible(), spacing: AppSpacing.s)
                    ],
                    spacing: AppSpacing.s
                ) {
                    ForEach(Array(visiblePatchOptions.dropFirst().enumerated()), id: \.element.id) { offset, option in
                        patchModuleCard(option, index: offset + 2, isFeatured: false)
                    }
                }
            }
            .id(selectedPatchCategory)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            if selectedPatchCategory == .loadout {
                Text(language.text("patch.note.aim_group"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            selectedPatchActionView
        }
        .padding(AppSpacing.l)
        .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
    }

    private var patchStudioCategoryNotice: some View {
        switch selectedPatchCategory {
        case .loadout:
            PatchCategoryNotice(
                title: language.text("patch.safety.aim_label"),
                detail: language.text("patch.safety.aim_detail"),
                tint: AppPalette.mint,
                icon: "checkmark.shield.fill"
            )
        case .visuals:
            PatchCategoryNotice(
                title: language.text("patch.safety.visuals_label"),
                detail: language.text("patch.safety.visuals_detail"),
                tint: AppPalette.amber,
                icon: "exclamationmark.triangle.fill"
            )
        case .antena:
            PatchCategoryNotice(
                title: language.text("patch.safety.antena_label"),
                detail: language.text("patch.safety.antena_detail"),
                tint: AppTheme.accent,
                icon: "antenna.radiowaves.left.and.right"
            )
        }
    }

    private var visualPatchPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(AppPalette.canvas)
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(height: 148)
                .frame(maxWidth: .infinity, alignment: .center)
            Label("TRYSTORE CLASSIC CHARACTER", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.textPrimary)
                .padding(10)
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
    }

    private var patchConsole: some View {
        VStack(spacing: AppSpacing.m) {
            HStack(alignment: .center, spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRYSTORE PATCHES")
                        .font(AppType.value())
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("FREE FIRE MAX  •  ORIGINAL MODULES")
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textTertiary)
                }
                Spacer(minLength: AppSpacing.s)
                if patchStore.isBusy {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(activeLegacyPatchCount)")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .monospacedDigit()
                        Text("/ \(DashboardPatchOption.unique.count)")
                            .font(AppType.value())
                            .foregroundStyle(AppPalette.textTertiary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(activeLegacyPatchCount) of \(DashboardPatchOption.unique.count) modules online")
                }
            }

            busStrip
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(AppPalette.canvas)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
    }

    /// One segment per module, using logo blue only for modules active on device.
    private var busStrip: some View {
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(DashboardPatchOption.unique) { option in
                    Capsule()
                        .fill(isPatchActive(option) ? AppPalette.brand : AppPalette.hairline.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
            HStack(spacing: 6) {
                Text(language.text("patch.module_bus"))
                    .font(AppType.label())
                    .foregroundStyle(AppPalette.textTertiary)
                Spacer(minLength: AppSpacing.s)
                Text("\(activeLegacyPatchCount) ONLINE")
                    .font(AppType.label())
                    .foregroundStyle(activeLegacyPatchCount > 0 ? AppPalette.brand : AppPalette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func patchModuleCard(_ option: DashboardPatchOption, index: Int, isFeatured: Bool) -> some View {
        let item = patchItem(for: option)
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false
        let isSelected = selectedPatchProjectName == option.id
        let isFavorite = appState.favorites.contains(option.id)
        let tint = isActive ? AppPalette.brand : (item == nil ? AppPalette.amber : patchTint)

        return PatchModuleCardView(
            title: option.title,
            icon: option.icon,
            status: patchRowLabel(item: item, isActive: isActive, isSelected: isSelected),
            tint: tint,
            indexLabel: String(format: "%02d", index),
            isActive: isActive,
            isSelected: isSelected,
            isFavorite: isFavorite,
            isBusy: patchStore.isBusy,
            isFeatured: isFeatured,
            onSelect: {
                AppHaptics.select()
                withAnimation(reduceMotion ? nil : AppMotion.tile) {
                    selectedPatchProjectName = option.id
                }
            },
            onToggleFavorite: {
                AppHaptics.tap()
                appState.toggleFavorite(option.id)
            }
        )
    }

    /// The TryStore logo blue is the single interactive accent in both categories.
    private var patchTint: Color {
        AppPalette.brand
    }

    private func isPatchActive(_ option: DashboardPatchOption) -> Bool {
        guard let item = patchItem(for: option) else { return false }
        return DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    private func patchRowLabel(item: PatchLibraryItem?, isActive: Bool, isSelected: Bool) -> String {
        if item == nil { return language.text("patch.status.missing") }
        if isActive { return language.text("patch.status.active") }
        return isSelected ? language.text("patch.status.selected") : language.text("patch.status.ready")
    }

    private func patchRowAccessibilityValue(item: PatchLibraryItem?, isActive: Bool, isSelected: Bool) -> String {
        if item == nil { return language.text("patch.detail.package_missing") }
        if isActive { return language.text("patch.detail.active") }
        return isSelected ? language.text("patch.detail.selected_ready") : language.text("patch.detail.available")
    }

    private var visiblePatchOptions: [DashboardPatchOption] {
        switch selectedPatchCategory {
        case .loadout: return DashboardPatchOption.loadout
        case .visuals: return DashboardPatchOption.visuals
        case .antena: return DashboardPatchOption.antena
        }
    }

    private var selectedPatchOption: DashboardPatchOption? {
        guard let selectedPatchProjectName else { return nil }
        return visiblePatchOptions.first { $0.id == selectedPatchProjectName }
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
        option.resolve(in: patchStore.items)
    }

    private var activeLegacyPatchCount: Int {
        DashboardPatchOption.unique.reduce(into: 0) { count, option in
            guard let item = patchItem(for: option),
                  DevicePatchService.latestReceipt(projectID: item.id) != nil else { return }
            count += 1
        }
    }

    private func activateSelectedPatch() {
        guard let option = selectedPatchOption else { return }
        guard let item = selectedPatchItem else {
            log("patch: activation refused — no unique package identity matched UI key \(option.projectName)")
            return
        }
        let resolvedName = item.project?.name ?? "locked package"
        log("patch: UI key \(option.projectName) resolved to \(resolvedName), file \(item.packageURL.lastPathComponent), id \(item.id.uuidString)")
        let shouldEnable = !selectedPatchIsActive
        beginPatchProgress(enabling: shouldEnable, title: option.title)

        patchStore.setEnabled(
            shouldEnable,
            for: item,
            group: option.group,
            reportsSuccess: true,
            reportsProgress: true,
            onSuccess: { enabled in PatchAudioFeedback.play(enabled: enabled) }
        )

        // A refused request (missing pairing tunnel, bad package) never starts,
        // so drop the card instead of leaving it frozen at zero.
        if !patchStore.isBusy {
            patchProgressTask?.cancel()
            patchProgressTask = nil
            showPatchProgress = false
            patchProgress = 0
        }
    }

    // MARK: - Patch progress

    private func beginPatchProgress(enabling: Bool, title: String) {
        patchOperationIsEnabling = enabling
        patchOperationFinished = false
        patchOperationSucceeded = true
        patchProgress = 0
        patchProgressStage = title
        patchProgressSub = language.text(enabling ? "patch.progress.applying" : "patch.progress.restoring")
        showPatchProgress = true
        if #available(iOS 16.1, *) {
            PatchActivityController.start(
                operation: language.text(enabling ? "patch.activating" : "patch.restoring"),
                detail: title,
                thermal: appState.thermalStateLabel
            )
        }

        patchProgressTask?.cancel()
        patchProgressTask = Task { @MainActor in
            // Floor only: the paced value keeps the card alive while the
            // measured progress arrives from the transaction itself.
            while !Task.isCancelled && patchProgress < 0.35 {
                try? await Task.sleep(nanoseconds: 26_000_000)
                if Task.isCancelled { return }
                patchProgress = min(0.35, patchProgress + 0.008)
            }
        }
    }

    /// Measured progress from the store wins whenever it is ahead of the floor.
    private var shownPatchProgress: Double {
        patchOperationFinished ? 1 : max(patchProgress, patchStore.operationProgress)
    }

    private func finishPatchProgress() {
        guard !patchOperationFinished else { return }
        patchOperationFinished = true
        patchProgressTask?.cancel()
        patchProgressTask = nil
        withAnimation(.easeOut(duration: 0.32)) {
            patchProgress = 1
        }
        if #available(iOS 16.1, *) {
            PatchActivityController.finish(detail: patchProgressFooter)
        }
    }

    private func dismissPatchProgress() {
        AppHaptics.tap()
        withAnimation(reduceMotion ? nil : AppMotion.surface) {
            showPatchProgress = false
        }
        patchProgress = 0
        patchOperationFinished = false
    }

    private var patchProgressOverlay: some View {
        let accent = patchOperationIsEnabling ? AppPalette.brand : AppPalette.amber

        return ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.l) {
                HStack(spacing: AppSpacing.s) {
                    Circle()
                        .fill(patchOperationFinished ? (patchOperationSucceeded ? AppPalette.brand : AppPalette.coral) : accent)
                        .frame(width: 6, height: 6)
                    Text(patchProgressHeader)
                        .font(AppType.label())
                        .tracking(1.1)
                        .foregroundStyle(AppPalette.textSecondary)
                    Spacer(minLength: AppSpacing.s)
                    Text("\(Int(shownPatchProgress * 100))%")
                        .font(AppType.digits(13))
                        .foregroundStyle(AppPalette.textPrimary)
                        .monospacedDigit()
                }

                ZStack {
                    Circle()
                        .stroke(AppPalette.hairline.opacity(0.60), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: max(0.004, shownPatchProgress))
                        .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.12), value: shownPatchProgress)

                    VStack(spacing: 2) {
                        Text("\(Int(shownPatchProgress * 100))")
                            .font(.system(size: 54, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(language.text(patchOperationIsEnabling ? "patch.activating" : "patch.restoring"))
                            .font(AppType.label())
                            .tracking(1.4)
                            .foregroundStyle(AppPalette.textTertiary)
                    }
                }
                .frame(width: 196, height: 196)

                VStack(spacing: 6) {
                    Text(patchProgressStage)
                        .font(AppType.label())
                        .tracking(1.0)
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(patchOperationFinished ? patchProgressFooter : patchProgressSub)
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .multilineTextAlignment(.center)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppPalette.hairline.opacity(0.55))
                        Capsule()
                            .fill(accent)
                            .frame(width: max(proxy.size.width * shownPatchProgress, shownPatchProgress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)

                if patchOperationFinished {
                    AppActionButton(
                        title: "DONE",
                        icon: "checkmark",
                        tint: patchOperationSucceeded ? AppPalette.mint : AppPalette.amber
                    ) {
                        dismissPatchProgress()
                    }
                } else {
                    Text(language.text("patch.progress.keep_open"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(AppPalette.surface)
            )
            .padding(.horizontal, AppSpacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(patchOperationFinished ? patchProgressFooter : language.text("patch.operation.title"))
    }

    private var patchProgressHeader: String {
        guard patchOperationFinished else { return language.text("patch.operation.title") }
        return language.text(patchOperationSucceeded ? "patch.operation.complete" : "patch.operation.failed")
    }

    private var patchProgressFooter: String {
        guard patchOperationSucceeded else { return language.text("patch.progress.failed") }
        return language.text(patchOperationIsEnabling ? "patch.progress.active" : "patch.progress.restored")
    }

    private var selectedPatchActionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let option = selectedPatchOption {
                HStack(spacing: AppSpacing.m) {
                    AppIconBadge(systemName: option.icon, tint: AppTheme.accent, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("patch.selected_patch"))
                            .font(AppType.label())
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
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(AppPalette.brand)
                            .accessibilityLabel(language.text("patch.detail.patch_active"))
                    }
                }
                if selectedPatchItem == nil {
                    Text(language.text("patch.detail.package_missing_long"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.amber)
                } else {
                    Text(selectedPatchIsActive ? language.text("patch.detail.active_hint") : language.text("patch.detail.ready_hint"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textSecondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AppTheme.accent)
                    Text(language.text("patch.detail.empty_hint"))
                        .font(AppType.body())
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: activateSelectedPatch) {
                HStack(spacing: 8) {
                    if patchStore.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: selectedPatchIsActive ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    }
                    Text(selectedPatchIsActive ? language.text("patch.action.restore") : language.text("patch.action.activate"))
                        .font(AppType.label())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppPalette.brand, in: Capsule())
            }
            .buttonStyle(AppPressButtonStyle())
            .disabled(selectedPatchItem == nil || patchStore.isBusy)
            .opacity(selectedPatchItem == nil || patchStore.isBusy ? 0.52 : 1)
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.tile)
    }

    // MARK: - Patch Category Enum
    private enum PatchCategory: CaseIterable, Identifiable {
        case loadout
        case visuals
        case antena

        var id: String {
            switch self {
            case .loadout: return "loadout"
            case .visuals: return "visuals"
            case .antena: return "antena"
            }
        }
        var titleKey: String {
            switch self {
            case .loadout: return "patch.mode.loadout"
            case .visuals: return "patch.mode.visuals"
            case .antena: return "patch.mode.antena"
            }
        }
        var icon: String {
            switch self {
            case .loadout: return "viewfinder"
            case .visuals: return "sparkles"
            case .antena: return "antenna.radiowaves.left.and.right"
            }
        }
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
    @Environment(\.appLanguage) private var language
    @State private var activity: Activity<LiveActivityState>?

    var body: some View {
        Group {
            if let activity = activity {
                LiveActivityBanner(activity: activity) {
                    await updateLiveActivity()
                }
            } else {
                Button(language.text("liveactivity.start")) {
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
            launchCount: appState.totalLaunches,
            progress: 0,
            operation: nil
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
            launchCount: appState.totalLaunches,
            progress: 0,
            operation: nil
        )
        await activity.update(using: updatedState)
    }
}

/// Mirrors a running patch or purge onto the Lock Screen and Dynamic Island.
/// Display needs a Widget Extension target holding an `ActivityConfiguration`
/// for `LiveActivityState`; `LiveActivityWidget.swift` is that widget, ready to
/// join such a target. Until it does, request() simply returns nothing on the
/// display side — which is why every call site is availability guarded.
@available(iOS 16.1, *)
enum PatchActivityController {
    static func start(operation: String, detail: String, thermal: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = LiveActivityState()
        let state = LiveActivityState.ContentState(
            isActive: true,
            cpuTemp: nil,
            gpuTemp: nil,
            thermalState: thermal,
            launchCount: 0,
            progress: 0,
            operation: operation
        )
        Task {
            for existing in Activity<LiveActivityState>.activities {
                if #available(iOS 16.2, *) {
                    await existing.end(nil, dismissalPolicy: .immediate)
                } else {
                    await existing.end(using: nil, dismissalPolicy: .immediate)
                }
            }
            _ = try? Activity<LiveActivityState>.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
        }
    }

    static func update(progress: Double) {
        Task {
            for activity in Activity<LiveActivityState>.activities {
                let current = activity.contentState
                let next = LiveActivityState.ContentState(
                    isActive: true,
                    cpuTemp: current.cpuTemp,
                    gpuTemp: current.gpuTemp,
                    thermalState: current.thermalState,
                    launchCount: current.launchCount,
                    progress: min(1, max(0, progress)),
                    operation: current.operation
                )
                await activity.update(using: next)
            }
        }
    }

    static func finish(detail: String) {
        Task {
            for activity in Activity<LiveActivityState>.activities {
                let current = activity.contentState
                let next = LiveActivityState.ContentState(
                    isActive: false,
                    cpuTemp: current.cpuTemp,
                    gpuTemp: current.gpuTemp,
                    thermalState: current.thermalState,
                    launchCount: current.launchCount,
                    progress: 1,
                    operation: detail
                )
                await activity.end(
                    using: next,
                    dismissalPolicy: .after(Date().addingTimeInterval(6))
                )
            }
        }
    }
}

@available(iOS 16.1, *)
struct LiveActivityBanner: View {
    let activity: Activity<LiveActivityState>
    let onRefresh: () async -> Void
    @Environment(\.appLanguage) private var language
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("liveactivity.title"))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                
                Label(language.text("liveactivity.thermal"), systemImage: "thermometer.medium")
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
