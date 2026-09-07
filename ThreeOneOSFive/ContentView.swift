import SwiftUI
import UIKit
import AVFoundation
import Combine

struct ContentView: View {
    private enum CharacterRegion: String, CaseIterable, Hashable {
        case head, chest, body, drag
        var title: String {
            switch self { case .head: return "HEAD"; case .chest: return "CHEST"; case .body: return "BODY"; case .drag: return "DRAG" }
        }
        var color: Color {
            switch self { case .head: return .cyan; case .chest: return AppTheme.accent; case .body: return .indigo; case .drag: return .orange }
        }
        var icon: String {
            switch self { case .head: return "scope"; case .chest: return "scope"; case .body: return "viewfinder"; case .drag: return "arrow.up.right.and.arrow.down.left" }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var patchStore = PatchProjectStore()
    @State private var patchOperationBusy = false
    @State private var patchMessage = "READY — SELECT AN ARCHIVO"
    @State private var aimDragEnabled = false
    @State private var aimNeckEnabled = false
    @State private var hspEnabled = false
    @State private var aimbotPechoEnabled = false
    @State private var hologramaArmasEnabled = false
    @State private var hsslaEnabled = false
    @State private var aimBodyEnabled = false
    @State private var hyperBalamagicaEnabled = false
    @State private var aimbotPechoMaxEnabled = false
    @State private var expiryRestoreCompleted = false
    @State private var licenseKeyInput = ""
    @State private var selectedRegion: CharacterRegion?
    @AppStorage("trystore.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage(AppTheme.accentStorageKey) private var accentIndex = AppTheme.defaultAccentIndex

    private let licenseGateEnabled = true
    private let totalArchivoCount = 5

    private var activeArchivoCount: Int { [aimDragEnabled, aimNeckEnabled, hspEnabled, aimbotPechoEnabled, hologramaArmasEnabled].filter { $0 }.count }
    private var activePatchCount: Int { activeArchivoCount }
    private var activeCharacterRegions: Set<CharacterRegion> {
        var regions = Set<CharacterRegion>()
        if aimDragEnabled { regions.insert(.drag) }
        if aimNeckEnabled || hspEnabled { regions.insert(.head) }
        if aimbotPechoEnabled { regions.insert(.chest) }
        if hologramaArmasEnabled { regions.insert(.body) }
        return regions
    }
    private var accessReady: Bool { licenseManager.isActive && appState.canUseProtectedFeatures }
    private var overallStatus: (title: String, detail: String, color: Color, icon: String) {
        if patchOperationBusy { return ("UPDATING", "Saving your Archivo selection", AppTheme.accent, "arrow.triangle.2.circlepath") }
        if !appState.isSupported || !appState.canUseProtectedFeatures { return ("REVIEW REQUIRED", "Device compatibility needs attention", .orange, "exclamationmark.shield.fill") }
        if licenseGateEnabled && !licenseManager.isActive { return ("ACCESS NEEDED", "Activate access to use Archivos", .orange, "lock.fill") }
        if activeArchivoCount == 0 { return ("READY TO BUILD", "Choose an Archivo to begin", AppTheme.accent, "slider.horizontal.3") }
        return ("READY TO REVIEW", "\(activeArchivoCount) of \(totalArchivoCount) Archivos active", .green, "checkmark.circle.fill")
    }

    var body: some View {
        ZStack {
            ControlDeckBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                    characterHUD
                    archivosHUD
                    bottomStatus
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { syncPatchStates(); enforceLicenseExpiry() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            syncPatchStates(); enforceLicenseExpiry()
            if licenseManager.isActive { patchMessage = "READY — SELECT AN ARCHIVO" }
        }
        .onChange(of: licenseManager.isActive) { active in
            if active { expiryRestoreCompleted = false } else { enforceLicenseExpiry() }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            licenseManager.expireIfNeeded(); enforceLicenseExpiry()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            AppLogo(size: 40)
                .padding(4)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppTheme.accent.opacity(0.34), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("TRY STORE")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(1.4)
                Text("CONTROL HUD")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.accent)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(overallStatus.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: overallStatus.color, radius: 6)
                Text(overallStatus.title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(overallStatus.color.opacity(0.35), lineWidth: 1))
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private var characterHUD: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.075, blue: 0.14),
                            Color(red: 0.008, green: 0.015, blue: 0.035)
                        ], startPoint: .top, endPoint: .bottom))

                Image("TryStoreTheme")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230)
                    .opacity(0.055)

                Image("CleanCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 330)
                    .padding(.top, 22)
                    .shadow(color: AppTheme.accent.opacity(0.18), radius: 18)

                hudTargetOverlay
            }
            .frame(height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.28), lineWidth: 1))

            waveformDivider

            Text(activeCharacterRegions.isEmpty
                 ? "SELECT A MODULE TO LINK A CHARACTER ZONE"
                 : "\(activeCharacterRegions.count) ZONE\(activeCharacterRegions.count == 1 ? "" : "S") LINKED")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.48))
                .padding(.vertical, 8)
        }
    }

    private var hudTargetOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                hudCallout(title: "DRAG", color: aimDragEnabled ? .green : .orange, active: aimDragEnabled)
                    .position(x: proxy.size.width * 0.19, y: proxy.size.height * 0.27)

                hudCallout(title: "HEAD", color: (aimNeckEnabled || hspEnabled) ? .green : .cyan, active: aimNeckEnabled || hspEnabled)
                    .position(x: proxy.size.width * 0.81, y: proxy.size.height * 0.28)

                hudCallout(title: "CHEST", color: aimbotPechoEnabled ? .green : AppTheme.accent, active: aimbotPechoEnabled)
                    .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.48)

                if activeCharacterRegions.contains(.body) {
                    Circle()
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 74, height: 74)
                        .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.65)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func hudCallout(title: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(active ? .white : color)
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(active ? color.opacity(0.20) : Color.black.opacity(0.62), in: Capsule())
                .overlay(Capsule().stroke(color.opacity(active ? 0.85 : 0.48), lineWidth: 1))

            Rectangle()
                .fill(color.opacity(active ? 0.90 : 0.55))
                .frame(width: 48, height: 1)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color, radius: active ? 6 : 2)
        }
        .shadow(color: color.opacity(active ? 0.34 : 0.10), radius: 8)
    }

    private var waveformDivider: some View {
        HStack(spacing: 0) {
            Rectangle().fill(AppTheme.accent.opacity(0.30)).frame(height: 1)
            WaveformMark()
                .stroke(AppTheme.accent.opacity(0.90), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 185, height: 26)
            Rectangle().fill(AppTheme.accent.opacity(0.30)).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    private var archivosHUD: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ARCHIVOS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.35)
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text("\(activeArchivoCount) / \(totalArchivoCount)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            hudRow(title: "DRAG", icon: "arrow.up.right.and.arrow.down.left", color: .orange, package: "DRAG.3105", state: $aimDragEnabled)
            hudRow(title: "HEAD", icon: "scope", color: .cyan, package: "CUELLO.3105", state: $aimNeckEnabled)
            hudRow(title: "CHEST", icon: "scope", color: AppTheme.accent, package: "PECHO.3105", state: $aimbotPechoEnabled)
            hudRow(title: "BODY", icon: "viewfinder", color: .indigo, package: "HEAD.3105", state: $hspEnabled)
            hudRow(title: "HOLO ARM", icon: "sparkles", color: .purple, package: "HOLO ARM.3105", state: $hologramaArmasEnabled)

            if !licenseManager.isActive { accessStrip }
        }
        .background(Color(red: 0.045, green: 0.035, blue: 0.075).opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 2)
    }

    private func hudRow(title: String, icon: String, color: Color, package: String, state: Binding<Bool>) -> some View {
        Button {
            selectedRegion = regionForPackage(package)
            togglePatch(packageFilename: package, state: state)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.wrappedValue ? .white : color)
                    .frame(width: 31, height: 31)
                    .background(state.wrappedValue ? color.opacity(0.30) : color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(.white)

                Spacer()

                Text(state.wrappedValue ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(state.wrappedValue ? .white : .white.opacity(0.38))
                    .frame(width: 34, height: 23)
                    .background(state.wrappedValue ? color.opacity(0.30) : Color.white.opacity(0.045), in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 12)
            .frame(height: 57)
            .background(state.wrappedValue ? color.opacity(0.18) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 53)
            }
        }
        .buttonStyle(.plain)
        .disabled(patchOperationBusy)
        .opacity(patchOperationBusy ? 0.58 : 1)
        .accessibilityLabel("\(title), \(state.wrappedValue ? "On" : "Off")")
    }

    private var accessStrip: some View {
        VStack(spacing: 9) {
            HStack {
                Label("ACCESS REQUIRED", systemImage: "lock.fill")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.orange)
                Spacer()
            }

            HStack(spacing: 7) {
                TextField("TRY-XXXX-XXXX-XXXX", text: $licenseKeyInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    licenseManager.activate(key: licenseKeyInput)
                } label: {
                    Text(licenseManager.isBusy ? "CHECKING" : "ACTIVATE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(licenseManager.isBusy || licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let message = licenseManager.message {
                Text(message)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.045))
    }

    private var bottomStatus: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SESSION")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.40))
                    Text(activeArchivoCount == 0 ? "READY FOR SELECTION" : "\(activeArchivoCount) MODULE\(activeArchivoCount == 1 ? "" : "S") ACTIVE")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Circle().fill(overallStatus.color).frame(width: 8, height: 8).shadow(color: overallStatus.color, radius: 7)
            }

            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.accent)
                Text(patchMessage)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer()
                if licenseManager.isActive {
                    Text(licenseManager.remainingText)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .padding(.top, 12)
    }

    private func regionForPackage(_ package: String) -> CharacterRegion? {
        switch package {
        case "DRAG.3105": return .drag
        case "CUELLO.3105": return .head
        case "PECHO.3105": return .chest
        case "HEAD.3105": return .body
        default: return nil
        }
    }

    private func enforceLicenseExpiry() {
        guard licenseGateEnabled,
              !licenseManager.isActive,
              !licenseManager.isBusy,
              !patchOperationBusy,
              !expiryRestoreCompleted else { return }
        let hasActivePatch = activePatchCount > 0 || [
            "CUELLO.3105", "DRAG.3105", "HEAD.3105", "PECHO.3105", "HOLO ARM.3105"
        ].contains { isPatchActive($0) }
        guard hasActivePatch else {
            expiryRestoreCompleted = true
            return
        }
        expiryRestoreCompleted = true
        restoreAllPatchesAfterExpiry()
    }

    private func restoreAllPatchesAfterExpiry() {
        guard !patchOperationBusy else { return }
        let packages = [
            "CUELLO.3105", "DRAG.3105", "HEAD.3105", "PECHO.3105", "HOLO ARM.3105"
        ]
        let restoreTargets = packages.compactMap { package -> (String, PatchTransactionReceipt)? in
            guard let item = patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(package) == .orderedSame }),
                  let receipt = DevicePatchService.latestReceipt(projectID: item.id) else { return nil }
            return (package, receipt)
        }
        patchOperationBusy = true
        patchMessage = "LICENSE EXPIRED — RESTORING ORIGINALS…"
        DispatchQueue.global(qos: .userInitiated).async {
            var restored = 0
            for (package, receipt) in restoreTargets {
                do {
                    try DevicePatchService.restore(receipt: receipt)
                    restored += 1
                } catch {
                    log("patch: expiry restore failed for \(package): \(error)")
                }
            }
            DispatchQueue.main.async {
                self.syncPatchStates()
                self.patchOperationBusy = false
                self.patchMessage = restored > 0 ? "LICENSE EXPIRED — ORIGINALS RESTORED" : "LICENSE EXPIRED — NO ACTIVE ARCHIVOS"
            }
        }
    }

    private func syncPatchStates() {
        aimDragEnabled = isPatchActive("DRAG.3105")
        aimNeckEnabled = isPatchActive("CUELLO.3105")
        hspEnabled = isPatchActive("HEAD.3105")
        aimbotPechoEnabled = isPatchActive("PECHO.3105")
        hologramaArmasEnabled = isPatchActive("HOLO ARM.3105")
    }

    private func isPatchActive(_ packageFilename: String) -> Bool {
        patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame })
            .flatMap { DevicePatchService.latestReceipt(projectID: $0.id) } != nil
    }

    private enum PatchActionResult {
        case applied
        case restored
        case unavailable(String)
    }

    private func setPatchState(for packageFilename: String, enabled: Bool) {
        switch packageFilename {
        case "DRAG.3105": aimDragEnabled = enabled
        case "CUELLO.3105": aimNeckEnabled = enabled
        case "HEAD.3105": hspEnabled = enabled
        case "PECHO.3105": aimbotPechoEnabled = enabled
        case "HOLO ARM.3105": hologramaArmasEnabled = enabled
        default: break
        }
    }

    private func togglePatch(packageFilename: String, state: Binding<Bool>) {
        guard !patchOperationBusy else { return }
        guard !licenseGateEnabled || licenseManager.isActive else {
            patchMessage = "LOCKED — ACTIVATE YOUR 30-DAY KEY ABOVE"
            return
        }
        guard appState.canUseProtectedFeatures else {
            patchMessage = "BLOCKED — DEVICE INTEGRITY REVIEW REQUIRED"
            return
        }
        guard let item = patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame }) else {
            patchMessage = "ERROR — PACKAGE NOT FOUND"
            log("patch: package not found: \(packageFilename)")
            return
        }

        let wasEnabled = state.wrappedValue
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        patchOperationBusy = true
        patchMessage = "PROCESSING — \(packageFilename)"
        let project = item.project
        let projectID = item.id

        DispatchQueue.global(qos: .userInitiated).async {
            let result: PatchActionResult
            do {
                if wasEnabled {
                    guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                        DispatchQueue.main.async {
                            self.setPatchState(for: packageFilename, enabled: false)
                            self.patchMessage = "OFF — NO ACTIVE ARCHIVO FOUND"
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    try DevicePatchService.restore(receipt: receipt)
                    result = .restored
                } else {
                    guard let project else {
                        DispatchQueue.main.async {
                            self.patchMessage = "LOCKED — PASSWORD REQUIRED"
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    _ = try DevicePatchService.apply(project: project)
                    result = .applied
                }
            } catch {
                result = .unavailable("FAILED — \(String(describing: error))")
            }

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.18)) {
                    switch result {
                    case .applied:
                        self.setPatchState(for: packageFilename, enabled: true)
                        self.patchMessage = "SUCCESS — BYPASS ACTIVATED"
                        PatchAudioFeedback.bypassActivated()
                        PatchAudioFeedback.announce(packageFilename, enabled: true)
                    case .restored:
                        self.setPatchState(for: packageFilename, enabled: false)
                        self.patchMessage = "SUCCESS — BYPASS DEACTIVATED"
                        PatchAudioFeedback.originalRestored()
                        PatchAudioFeedback.announce(packageFilename, enabled: false)
                    case .unavailable(let message):
                        self.patchMessage = message
                    }
                    self.patchOperationBusy = false
                }
            }
        }
    }

    private func openGame(scheme: String) {
        guard !licenseGateEnabled || licenseManager.isActive else {
            patchMessage = "LOCKED — ACTIVATE YOUR 30-DAY KEY ABOVE"
            return
        }
        guard appState.canUseProtectedFeatures else {
            patchMessage = "BLOCKED — DEVICE INTEGRITY REVIEW REQUIRED"
            return
        }
        guard let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            log("launch: \(scheme) success=\(success)")
        }
    }
}

private struct WaveformMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let step = rect.width / 8
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: step * 0.8, y: midY))
        path.addLine(to: CGPoint(x: step * 0.95, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: step * 1.08, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: step * 1.22, y: midY))
        path.addLine(to: CGPoint(x: step * 3.0, y: midY))
        path.addLine(to: CGPoint(x: step * 3.15, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: step * 3.30, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: step * 3.45, y: midY))
        path.addLine(to: CGPoint(x: step * 5.25, y: midY))
        path.addLine(to: CGPoint(x: step * 5.40, y: rect.minY + 5))
        path.addLine(to: CGPoint(x: step * 5.55, y: rect.maxY - 5))
        path.addLine(to: CGPoint(x: step * 5.70, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}

private struct PatchOptionCard: View {
    let name: String
    let target: String
    let fileExcerpt: String
    let color: Color
    @Binding var isEnabled: Bool
    let isBusy: Bool
    let isCompact: Bool
    let showFileExcerpt: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(isEnabled ? 0.25 : 0.11))
                        .frame(width: 48, height: 48)
                    Image(systemName: isEnabled ? "bolt.fill" : "scope")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    HStack(spacing: 6) {
                        Text(target)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.65)
                            .foregroundStyle(color)
                            .lineLimit(1)
                        if showFileExcerpt {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.30))
                            Text(fileExcerpt)
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(0.65)
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                    Text(isEnabled ? "ARCHIVO ACTIVE" : "TAP TO ACTIVATE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(isEnabled ? .green : .white.opacity(0.40))
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(isEnabled ? "ON" : "OFF")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(isEnabled ? .green : .white.opacity(0.56))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background((isEnabled ? Color.green : Color.white).opacity(0.10), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.26))
                }
            }
            .padding(isCompact ? 10 : 12)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 68 : 82, alignment: .leading)
            .background {
                if isEnabled {
                    LinearGradient(colors: [color.opacity(0.20), Color.black.opacity(0.52)], startPoint: .leading, endPoint: .trailing)
                } else {
                    LinearGradient(colors: [color.opacity(0.07), Color.black.opacity(0.43)], startPoint: .leading, endPoint: .trailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(isEnabled ? color.opacity(0.78) : color.opacity(0.24), lineWidth: isEnabled ? 1.4 : 1)
            )
            .shadow(color: isEnabled ? color.opacity(0.18) : .black.opacity(0.18), radius: isEnabled ? 12 : 5, y: 4)
        }
        .buttonStyle(GoldPatchButtonStyle())
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .accessibilityLabel("\(name), \(target), \(showFileExcerpt ? fileExcerpt : "file hidden"), \(isEnabled ? "On" : "Off")")
    }
}

private struct GoldPatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private enum PatchAudioFeedback {
    private static var activationPlayer: AVAudioPlayer?
    private static var deactivationPlayer: AVAudioPlayer?

    static func bypassActivated() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? session.setActive(true, options: [])

        guard let url = Bundle.main.url(forResource: "PatchActivated", withExtension: "mp3") else { log("audio: PatchActivated.mp3 is missing"); return }

        do {
            activationPlayer = try AVAudioPlayer(contentsOf: url)
            activationPlayer?.prepareToPlay()
            activationPlayer?.play()
        } catch {
            log("audio: activation sound unavailable: \(error)")
        }
    }

    static func originalRestored() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? session.setActive(true, options: [])

        guard let url = Bundle.main.url(forResource: "PatchDeactivated", withExtension: "mp3") else { log("audio: PatchDeactivated.mp3 is missing"); return }

        do {
            deactivationPlayer = try AVAudioPlayer(contentsOf: url)
            deactivationPlayer?.prepareToPlay()
            deactivationPlayer?.play()
        } catch {
            log("audio: deactivation sound unavailable: \(error)")
        }
    }

    static func announce(_ packageFilename: String, enabled: Bool) { }
}

struct ControlDeckBackdrop: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.004, green: 0.010, blue: 0.026)
                Image("TryStoreTheme")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width * 1.12, height: proxy.size.height * 0.74)
                    .opacity(0.18)
                    .blur(radius: 1.2)
                    .scaleEffect(animate ? 1.04 : 1.0)
                    .offset(y: animate ? -12 : 12)
                    .mask(LinearGradient(colors: [.clear, .white.opacity(0.72), .white.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom))
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 310, height: 310)
                    .blur(radius: 80)
                    .offset(x: animate ? 130 : -120, y: -proxy.size.height * 0.30)
                Circle()
                    .fill(AppTheme.palette[4].color.opacity(0.08))
                    .frame(width: 250, height: 250)
                    .blur(radius: 85)
                    .offset(x: animate ? -110 : 100, y: proxy.size.height * 0.26)
                Circle()
                    .fill(Color.purple.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 78)
                    .offset(x: animate ? -80 : 120, y: -proxy.size.height * 0.08)
                GridOverlay()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
        }
    }
}

private struct ParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                canvas(time: 0)
            } else {
                TimelineView(.animation) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            for index in 0..<24 {
                let seed = Double(index)
                let baseX = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1.0)
                let baseY = (seed * 0.38196601125 + 0.17).truncatingRemainder(dividingBy: 1.0)
                let x = (baseX + sin(time * 0.10 + seed * 1.7) * 0.035).truncatingRemainder(dividingBy: 1.0) * size.width
                let fall = time * (0.014 + seed.truncatingRemainder(dividingBy: 5.0) * 0.0015)
                let y = (baseY + fall + cos(time * 0.08 + seed * 1.2) * 0.025 + 1.0).truncatingRemainder(dividingBy: 1.0) * size.height
                let radius = 1.0 + seed.truncatingRemainder(dividingBy: 3.0) * 0.55
                let pulse = 0.55 + 0.45 * sin(time * 0.7 + seed)
                let color = index.isMultiple(of: 4) ? Color.cyan : AppTheme.accent
                let alpha = (0.16 + seed.truncatingRemainder(dividingBy: 4.0) * 0.035) * pulse
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                let glow = rect.insetBy(dx: -radius * 2.8, dy: -radius * 2.8)
                context.fill(Path(ellipseIn: glow), with: .color(color.opacity(alpha * 0.16)))
            }
        }
    }
}

private struct FallingNeonParticles: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: Date(), by: 0.10)) { timeline in
                fallingCanvas(time: timeline.date.timeIntervalSinceReferenceDate, size: proxy.size)
            }
        }
    }

    private func fallingCanvas(time: TimeInterval, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let width = max(canvasSize.width, size.width)
            let height = max(canvasSize.height, size.height)
            for index in 0..<30 {
                let seed = Double(index)
                let x = (seed * 0.754877666 + sin(seed * 2.1) * 0.025).truncatingRemainder(dividingBy: 1.0) * width
                let speed = 0.010 + seed.truncatingRemainder(dividingBy: 5.0) * 0.0014
                let y = (seed * 0.413731 + time * speed).truncatingRemainder(dividingBy: 1.0) * height
                let length = 3.0 + seed.truncatingRemainder(dividingBy: 5.0) * 2.0
                let radius = 0.8 + seed.truncatingRemainder(dividingBy: 3.0) * 0.42
                let pulse = 0.62 + 0.38 * sin(time * 0.9 + seed)
                let color = index.isMultiple(of: 5) ? Color.white : (index.isMultiple(of: 2) ? Color.cyan : AppTheme.accent)
                let alpha = (0.42 + seed.truncatingRemainder(dividingBy: 4.0) * 0.045) * pulse
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y))
                streak.addLine(to: CGPoint(x: x, y: y + length))
                context.stroke(streak, with: .color(color.opacity(alpha * 0.95)), lineWidth: radius * 1.35)
                let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color.opacity(alpha)))
            }
        }
        .drawingGroup(opaque: false, colorMode: .linear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AnimatedAtmosphere: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: Date(), by: 0.12)) { timeline in
                atmosphere(time: timeline.date.timeIntervalSinceReferenceDate, size: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func atmosphere(time: TimeInterval, size: CGSize) -> some View {
        let phase = time * 0.12
        let driftX = CGFloat(sin(phase) * Double(size.width * 0.28))
        let driftY = CGFloat(cos(phase * 0.83) * Double(size.height * 0.12))
        return ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 310, height: 310)
                .blur(radius: 54)
                .offset(x: -size.width * 0.34 + driftX, y: -size.height * 0.30 + driftY)
            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 270, height: 270)
                .blur(radius: 56)
                .offset(x: size.width * 0.34 - driftX, y: size.height * 0.18 - driftY)
            Circle()
                .fill(AppTheme.accent.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 46)
                .offset(x: driftX * 0.5, y: size.height * 0.34)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 44
            stride(from: CGFloat(0), through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(AppTheme.accent.opacity(0.045)), lineWidth: 1)
        }
    }
}
