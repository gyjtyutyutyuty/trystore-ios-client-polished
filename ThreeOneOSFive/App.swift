import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseManager = LicenseManager()
    @AppStorage("trystore.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("trystore.themeMode") private var themeMode = "dark"
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator();
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
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
                if !hasCompletedOnboarding {
                    OnboardingView { hasCompletedOnboarding = true }
                } else if !licenseManager.isActive {
                    AccessGateView()
                        .environmentObject(licenseManager)
                } else {
                    ContentView()
                        .environmentObject(licenseManager)
                }
            }
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
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
                .onAppear {
                    licenseManager.beginLaunchSession()
                    appState.detectSupport()
                    checkForUpdate()
                }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseManager.beginLaunchSession()
                appState.detectSupport()
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .preferredColorScheme(.dark)
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false
    @Published private(set) var integrityStatus: DeviceIntegrityReport.Status = .trusted
    @Published private(set) var integrityCheckedAt: Date?
    @Published private(set) var isReconcilingPatches = false

    private var autoRunAttempted = false

    var canUseProtectedFeatures: Bool {
        isSupported && integrityStatus.isTrusted
    }

    var integrityLabel: String { integrityStatus.label }
    var integrityDetail: String { integrityStatus.detail }

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    @MainActor
    func reconcilePatchesIfNeeded(licenseManager: LicenseManager) {
        guard (licenseManager.requiresPatchRestore || licenseManager.isExpired), !isReconcilingPatches else { return }
        isReconcilingPatches = true
        log("patch: reconciling existing receipts before protected access")
        DispatchQueue.global(qos: .userInitiated).async {
            let restored = DevicePatchService.restoreAllExistingReceipts()
            DispatchQueue.main.async {
                self.isReconcilingPatches = false
                if restored > 0 {
                    licenseManager.markPatchRestoreCompleted()
                    log("patch: launch reconciliation restored \(restored) receipt(s)")
                } else {
                    log("patch: launch reconciliation found no restorable receipts")
                }
            }
        }
    }

    func detectSupport() {
        let integrity = DeviceIntegrityReport.evaluate()
        integrityStatus = integrity.status
        integrityCheckedAt = integrity.checkedAt
        if !integrity.status.isTrusted {
            log("security: protected actions blocked — \(integrity.status.detail)")
        }

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
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            log("app: iPad safety mode — automatic kernel exploit disabled")
            return
        }
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
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            log("app: iPad safety mode — kernel exploit request blocked")
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
