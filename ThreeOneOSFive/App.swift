import SwiftUI
import UIKit

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

@_silgen_name("ALGetGrappaToken")
private func retainGrappaTokenSymbol(
    _ version: UInt32,
    _ deviceType: UInt32,
    _ protocolVersion: UInt32,
    _ output: UnsafeMutablePointer<UInt8>?,
    _ maximumLength: Int,
    _ outputLength: UnsafeMutablePointer<Int>?,
    _ errorBuffer: UnsafeMutablePointer<CChar>?,
    _ errorLength: Int
) -> Int32

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var deviceTiltMotion = DeviceTiltMotion()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("settings_reduce_motion_enabled") private var appReduceMotionEnabled = false

    init() {
        _ = retainGrappaTokenSymbol(0, 0, 0, nil, 0, nil, nil, 0)
        setupLogCapture()
        PairingController.removeLegacyTransportLogs()
        SecuritySuiteProbe.denyDebugger()
        ["activation_granted", "activation_account", "activation_password", "activation_uuid", "activation_expires_at"]
            .forEach(UserDefaults.standard.removeObject(forKey:))
        log("app: Support Patch launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || appReduceMotionEnabled
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.securityBlocked {
                    SecurityBlockView(reason: appState.securityMessage)
                } else if showOnboarding {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            showOnboarding = false
                        }
                        licenseManager.beginLaunchSession()
                        appState.detectSupport()
                        checkForUpdate()
                    }
                } else if licenseManager.isActive {
                    ContentView()
                } else {
                    LicenseGateView()
                }
            }
            .environmentObject(appState)
            .environmentObject(licenseManager)
            .environmentObject(patchDraftCoordinator)
            .environmentObject(fileOperationCoordinator)
            .environmentObject(deviceTiltMotion)
            .environment(\.appReduceMotion, effectiveReduceMotion)
            .environment(\.appLanguage, language)
            .environment(\.locale, language.locale)
            // The design system scales with the user's text size now; the clamp
            // keeps 44 pt hit targets and gauge rings intact at the extremes.
            .dynamicTypeSize(.xSmall ... .accessibility1)
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding && licenseManager.isActive)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .onAppear {
                appState.recordLaunch()
                appState.refreshThermalState()
                appState.evaluateRuntimeSecurity()
                if scenePhase == .active && !effectiveReduceMotion {
                    deviceTiltMotion.start()
                }
                if !showOnboarding {
                    licenseManager.beginLaunchSession()
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                appState.refreshThermalState()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active && !effectiveReduceMotion {
                    deviceTiltMotion.start()
                } else {
                    deviceTiltMotion.stop()
                }
                guard phase == .active else { return }
                appState.evaluateRuntimeSecurity()
                appState.refreshThermalState()
                guard !showOnboarding else { return }
                licenseManager.beginLaunchSession()
                appState.detectSupport()
            }
            .onChange(of: effectiveReduceMotion) { isReduced in
                if isReduced {
                    deviceTiltMotion.stop()
                } else if scenePhase == .active {
                    deviceTiltMotion.start()
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard scenePhase == .active else { continue }
                    appState.evaluateRuntimeSecurity()
                    appState.refreshThermalState()
                }
            }
        }
    }
}

struct SecurityBlockView: View {
    let reason: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.red)
                Text("Ứng dụng đã bị khóa")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(reason)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: 420)
            }
            .padding(24)
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false
    @Published var securityBlocked = false
    @Published var securityMessage = ""
    private var autoRunAttempted = false
    @AppStorage("app_launch_count") private var launchCount = 0
    var totalLaunches: Int {
        launchCount
    }
    func recordLaunch() {
        launchCount &+= 1
    }
    @AppStorage("patch_favorites") private var favoritesData: Data = Data()
    var favorites: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: favoritesData)) ?? []
    }
    func toggleFavorite(_ projectName: String) {
        var newFavorites: Set<String>
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: favoritesData) {
            newFavorites = decoded
        } else {
            newFavorites = []
        }
        if newFavorites.contains(projectName) {
            newFavorites.remove(projectName)
        } else {
            newFavorites.insert(projectName)
        }
        if let encoded = try? JSONEncoder().encode(newFavorites) {
            favoritesData = encoded
        }
    }
    // Patch configuration slots (save/load)
    @AppStorage("patch_slot_1") private var slot1Name: String = ""
    @AppStorage("patch_slot_2") private var slot2Name: String = ""
    @AppStorage("patch_slot_3") private var slot3Name: String = ""
    @AppStorage("patch_slot_4") private var slot4Name: String = ""
    @AppStorage("patch_slot_5") private var slot5Name: String = ""
    var slotNames: [String] {
        [slot1Name, slot2Name, slot3Name, slot4Name, slot5Name]
    }
    func saveSlot(_ slot: Int, name: String) {
        guard 1...5 ~= slot else { return }
        switch slot {
        case 1: slot1Name = name
        case 2: slot2Name = name
        case 3: slot3Name = name
        case 4: slot4Name = name
        case 5: slot5Name = name
        default: return
        }
    }
    func loadSlot(_ slot: Int) -> String? {
        guard 1...5 ~= slot else { return nil }
        switch slot {
        case 1: return slot1Name
        case 2: return slot2Name
        case 3: return slot3Name
        case 4: return slot4Name
        case 5: return slot5Name
        default: return nil
        }
    }
    // Stats overlay toggle
    @AppStorage("stats_overlay_enabled") var showStatsOverlay = false
    var statsOverlayItems: [String] {
        showStatsOverlay ? ["Thermal State", "Launch Count"] : []
    }
    @Published private(set) var thermalStateLabel = "Unknown"

    func refreshThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalStateLabel = "Nominal"
        case .fair:
            thermalStateLabel = "Fair"
        case .serious:
            thermalStateLabel = "Serious"
        case .critical:
            thermalStateLabel = "Critical"
        @unknown default:
            thermalStateLabel = "Unknown"
        }
    }

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    private func markKernelExploitUnsupported() {
        let version = AppInfo.versionTuple
        guard let reason = KernelExploit.unsupportedReason(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        ) else { return }

        let status = ExploitStatus.unsupported(reason)
        guard exploitStatus != status else { return }
        exploitStatus = status
        log("kexploit: skipped — \(reason)")
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func evaluateRuntimeSecurity() {
        switch RuntimeProbe.currentState() {
        case .ok, .unavailable:
            securityBlocked = false
            securityMessage = ""
        case .blockedByDebug:
            securityBlocked = true
            securityMessage = "Debugger đang được phát hiện."
        case .blockedBySimulator:
            securityBlocked = true
            securityMessage = "Môi trường giả lập không được phép chạy phiên bản này."
        }
    }

    func detectSupport() {
        evaluateRuntimeSecurity()
        if securityBlocked { return }
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else {
            markKernelExploitUnsupported()
            return
        }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        guard kernelExploitApplicable else {
            markKernelExploitUnsupported()
            return
        }
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
