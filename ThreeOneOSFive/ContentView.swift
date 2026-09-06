import SwiftUI
import UIKit
import AVFoundation
import Combine

struct ContentView: View {
    private struct ActiveModuleSummary: Identifiable {
        let id: String
        let name: String
        let target: String
        let color: Color
    }

    private enum GameFilter: String, CaseIterable {
        case all
        case normal
        case max

        var title: String {
            switch self {
            case .all: return "ALL"
            case .normal: return "NORMAL"
            case .max: return "MAX"
            }
        }

        var target: String? {
            switch self {
            case .all: return nil
            case .normal: return "FREE FIRE NORMAL"
            case .max: return "FREE FIRE MAX"
            }
        }
    }

    private enum CharacterRegion: String, CaseIterable, Hashable {
        case head
        case chest
        case body
        case drag

        var title: String {
            switch self {
            case .head: return "HEAD"
            case .chest: return "CHEST"
            case .body: return "BODY"
            case .drag: return "DRAG"
            }
        }

        var color: Color {
            switch self {
            case .head: return .cyan
            case .chest: return .green
            case .body: return AppTheme.accent
            case .drag: return AppTheme.palette[2].color
            }
        }

        var icon: String {
            switch self {
            case .head: return "scope"
            case .chest: return "scope"
            case .body: return "viewfinder"
            case .drag: return "arrow.up.right.and.arrow.down.left"
            }
        }

        var offset: CGFloat {
            switch self {
            case .head: return -82
            case .chest: return -20
            case .body: return 48
            case .drag: return 16
            }
        }

        var diameter: CGFloat {
            switch self {
            case .head: return 58
            case .chest: return 78
            case .body: return 126
            case .drag: return 92
            }
        }
    }

    private enum PatchSection: String, CaseIterable {
        case aim
        case visual

        var title: String {
            switch self {
            case .aim: return "AIM OPTIONS"
            case .visual: return "VISUAL OPTIONS"
            }
        }

        var icon: String {
            switch self {
            case .aim: return "scope"
            case .visual: return "eye.fill"
            }
        }

        var caption: String {
            switch self {
            case .aim: return "PRECISION MODULES"
            case .visual: return "DISPLAY MODULES"
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var patchStore = PatchProjectStore()
        @State private var patchOperationBusy = false
    @State private var patchMessage = "READY — SELECT A PATCH"
    @State private var aimDragEnabled = false
    @State private var aimNeckEnabled = false
    @State private var hsslaEnabled = false
    @State private var hspEnabled = false
    @State private var selectedGameFilter: GameFilter = .all
    @State private var patchSearchText = ""
    @State private var showRemoveTracesConfirmation = false
    @State private var aimBodyEnabled = false
    @State private var hyperBalamagicaEnabled = false
    @State private var aimbotPechoEnabled = false
    @State private var aimbotPechoMaxEnabled = false
    @State private var hologramaArmasEnabled = false
    @State private var expiryRestoreCompleted = false
    @State private var removeTracesBusy = false
    @State private var selectedPatchSection: PatchSection = .aim
    @State private var chestPulse = false
    @State private var showViewControls = false
    @State private var showAppearance = false
    @State private var showQuickStart = true
    @AppStorage("trystore.compactPatchRows") private var compactPatchRows = false
    @AppStorage("trystore.showFileFragments") private var showFileFragments = true
    @AppStorage("trystore.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage(AppTheme.accentStorageKey) private var accentIndex = AppTheme.defaultAccentIndex

    private let totalPatchCount = 9
    // Temporary local/demo mode: key access is disabled, but device-integrity checks remain enforced.
    private let licenseGateEnabled = false

    private var activePatchCount: Int {
        [
            aimDragEnabled, aimNeckEnabled, hsslaEnabled, hspEnabled,
            aimBodyEnabled, hyperBalamagicaEnabled, aimbotPechoEnabled,
            aimbotPechoMaxEnabled, hologramaArmasEnabled
        ].filter { $0 }.count
    }

    private var activeCharacterRegions: Set<CharacterRegion> {
        var regions = Set<CharacterRegion>()
        if aimDragEnabled { regions.insert(.drag) }
        if aimNeckEnabled || hspEnabled { regions.insert(.head) }
        if aimBodyEnabled || aimbotPechoEnabled || aimbotPechoMaxEnabled { regions.insert(.chest) }
        if hsslaEnabled || hyperBalamagicaEnabled || hologramaArmasEnabled { regions.insert(.body) }
        return regions
    }

    private var characterPreviewStatus: String {
        let titles = CharacterRegion.allCases
            .filter { activeCharacterRegions.contains($0) }
            .map(\.title)
        return titles.isEmpty ? "STANDBY LOADOUT" : titles.joined(separator: " + ") + " LINKED"
    }

    private var activeModules: [ActiveModuleSummary] {
        var modules: [ActiveModuleSummary] = []
        if aimDragEnabled { modules.append(.init(id: "AimDragFreeFire.3105", name: "MIRA ARRASTRE HS ALTO✅", target: "FREE FIRE NORMAL", color: AppTheme.accent)) }
        if aimNeckEnabled { modules.append(.init(id: "AimNeckFreeFire.3105", name: "MIRA CUELLO", target: "FREE FIRE NORMAL", color: .cyan)) }
        if hsslaEnabled { modules.append(.init(id: "HSSLA.3105", name: "HSLA", target: "FREE FIRE MAX", color: AppTheme.accent)) }
        if hspEnabled { modules.append(.init(id: "HSPESCOSEMANTENA.3105", name: "CUELLO SIN ANTENA", target: "FREE FIRE MAX", color: AppTheme.palette[1].color)) }
        if aimBodyEnabled { modules.append(.init(id: "AimBody.3105", name: "HS PECHO HYPER", target: "FREE FIRE MAX", color: AppTheme.palette[4].color)) }
        if hyperBalamagicaEnabled { modules.append(.init(id: "HYPERBALAMAGICA.3105", name: "HYPER BALAMÁGICA", target: "FREE FIRE NORMAL", color: AppTheme.accent)) }
        if aimbotPechoEnabled { modules.append(.init(id: "AimbotPecho.3105", name: "AIMBOT PECHO", target: "FREE FIRE NORMAL", color: AppTheme.palette[2].color)) }
        if aimbotPechoMaxEnabled { modules.append(.init(id: "AimbotPechoMax.3105", name: "AIMBOT PECHO MAX", target: "FREE FIRE MAX", color: AppTheme.palette[2].color)) }
        if hologramaArmasEnabled { modules.append(.init(id: "Shaders.3105", name: "HOLOGRAMA ARMAS", target: "FREE FIRE MAX", color: AppTheme.palette[5].color)) }
        return modules
    }

    private var sessionStateLabel: String {
        if patchOperationBusy { return "UPDATING" }
        if licenseGateEnabled && !licenseManager.isActive { return "LICENSE REQUIRED" }
        if !appState.canUseProtectedFeatures { return "REVIEW REQUIRED" }
        return activePatchCount == 0 ? "SYSTEM READY" : "LOADOUT READY"
    }

    private var sessionStateColor: Color {
        if patchOperationBusy { return AppTheme.accent }
        if (licenseGateEnabled && !licenseManager.isActive) || !appState.canUseProtectedFeatures { return .red }
        return activePatchCount == 0 ? .green : AppTheme.accent
    }

    var body: some View {
        ZStack {
            ControlDeckBackdrop()
                .id(accentIndex)
                .ignoresSafeArea()
            AnimatedAtmosphere()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topBar
                    heroPanel
                    telemetryStrip
                    characterPreviewPanel
                    referencePatchConsole
                    sessionOverview
                    enterGamePanel
                    socialLinksPanel
                    creditsPanel
                    footerBar
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            FallingNeonParticles()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .blendMode(.screen)
                .opacity(0.92)
                .zIndex(20)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Remove app-owned traces from both Free Fire apps?", isPresented: $showRemoveTracesConfirmation, titleVisibility: .visible) {
            Button("Remove traces", role: .destructive) {
                removeTraces()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the permitted Library/Caches and tmp folders will be touched.")
        }
        .onAppear {
            syncPatchStates()
            enforceLicenseExpiry()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            syncPatchStates()
            enforceLicenseExpiry()
            if licenseManager.isActive {
                patchMessage = "READY — SELECT A PATCH"
            }
        }
        .onChange(of: licenseManager.isActive) { active in
            if active {
                expiryRestoreCompleted = false
            } else {
                enforceLicenseExpiry()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            licenseManager.expireIfNeeded()
            enforceLicenseExpiry()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                    )
                AppLogo(size: 42)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("TRY STORE")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(2.7)
                    .foregroundStyle(.white)
                Text("SECURE EDITION")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(AppTheme.accent)
            }

            Spacer(minLength: 8)
            systemStatusPill
        }
    }

    private var systemStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.canUseProtectedFeatures ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: appState.canUseProtectedFeatures ? .green : .red, radius: 5)
            Text(appState.canUseProtectedFeatures ? "READY" : "REVIEW")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(appState.canUseProtectedFeatures ? .green : .red)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.black.opacity(0.36), in: Capsule())
        .overlay(Capsule().stroke((appState.canUseProtectedFeatures ? Color.green : Color.red).opacity(0.34), lineWidth: 1))
    }

    private var heroPanel: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.08, blue: 0.30), Color(red: 0.018, green: 0.025, blue: 0.10), Color(red: 0.006, green: 0.012, blue: 0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LinearGradient(colors: [.cyan.opacity(0.35), .purple.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .padding(2)
                )

            Circle()
                .fill(AppTheme.accent.opacity(0.13))
                .frame(width: 160, height: 160)
                .blur(radius: 2)
                .offset(x: 70, y: -56)

            Circle()
                .fill(Color.purple.opacity(0.16))
                .frame(width: 120, height: 120)
                .blur(radius: 28)
                .offset(x: -92, y: 74)

            AppLogo(size: 128)
                .opacity(0.08)
                .blur(radius: 0.4)
                .offset(x: 70, y: 28)

            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 156, height: 188)
                .opacity(0.72)
                .offset(x: 58, y: 22)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("TRY STORE / SECURE EDITION")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.7)
                            .foregroundStyle(AppTheme.accent)
                        Text("Patch smarter.\nPlay cleaner.")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.72)
                        Text("Build a focused loadout, preview every link, then launch with confidence.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    ZStack {
                        Circle()
                            .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0.06, to: 0.72)
                            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 58, height: 58)
                            .rotationEffect(.degrees(-38))
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 21, weight: .black))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                HStack(spacing: 8) {
                    heroBadge(icon: "lock.fill", text: "LOCAL CONTROL")
                    heroBadge(icon: "sparkles", text: "EXOTIC BLUE CORE")
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
        }
        .frame(minHeight: 184)
    }

    private func heroBadge(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.45)
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.28), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 1))
    }

    private var characterPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CHARACTER PREVIEW")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.45)
                        .foregroundStyle(AppTheme.accent)
                    Text(characterPreviewStatus)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Label(activeCharacterRegions.isEmpty ? "READY" : "LIVE", systemImage: activeCharacterRegions.isEmpty ? "person.fill" : "scope")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.65)
                    .foregroundStyle(activeCharacterRegions.isEmpty ? .white.opacity(0.48) : .green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background((activeCharacterRegions.isEmpty ? Color.white : Color.green).opacity(0.10), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.08, blue: 0.17), Color(red: 0.004, green: 0.012, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                AppLogo(size: 216)
                    .opacity(0.26)
                    .blendMode(.screen)
                    .blur(radius: 0.2)
                    .offset(x: 64, y: 2)
                Circle()
                    .fill(AppTheme.accent.opacity(0.13))
                    .frame(width: 190, height: 190)
                    .blur(radius: 44)
                    .offset(x: 58, y: -24)
                ParticleField()
                    .opacity(0.68)
                Image("CleanCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .padding(.horizontal, 18)
                    .shadow(color: AppTheme.accent.opacity(0.28), radius: 18, y: 6)
                    .opacity(activeCharacterRegions.isEmpty ? 0.88 : 1)

                ForEach(CharacterRegion.allCases.filter { activeCharacterRegions.contains($0) }, id: \.self) { region in
                    characterRegionMarker(region)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 270)
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    chestPulse = true
                }
            }

            Text(activeCharacterRegions.isEmpty ? "Activate a patch to link its head, chest, body, or drag target to the character." : "Live links: \(characterPreviewStatus.replacingOccurrences(of: " ACTIVE", with: ""))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke((activeCharacterRegions.isEmpty ? AppTheme.accent : Color.green).opacity(0.20), lineWidth: 1))
        .animation(.easeOut(duration: 0.22), value: activeCharacterRegions)
    }

    private func characterRegionMarker(_ region: CharacterRegion) -> some View {
        ZStack {
            Circle()
                .stroke(region.color.opacity(0.92), lineWidth: 2.5)
                .frame(width: region.diameter, height: region.diameter)
                .shadow(color: region.color, radius: chestPulse ? 15 : 6)
                .scaleEffect(chestPulse ? 1.05 : 0.96)
            Circle()
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
                .frame(width: region.diameter * 0.62, height: region.diameter * 0.62)
            Image(systemName: region.icon)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(region.color)
            Text(region.title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72), in: Capsule())
                .offset(y: region.diameter / 2 + 13)
        }
        .offset(y: region.offset)
    }

    private var referencePatchConsole: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PATCHES", systemImage: "scope")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.25)
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text("SWIPE / SELECT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
            }
            compactPatchButton(title: "DRAG", subtitle: "Aim drag", icon: "arrow.up.right.and.arrow.down.left", color: AppTheme.accent, package: "AimDragFreeFire.3105", state: $aimDragEnabled)
            compactPatchButton(title: "NECK", subtitle: "Head link", icon: "scope", color: .cyan, package: "AimNeckFreeFire.3105", state: $aimNeckEnabled)
            compactPatchButton(title: "CHEST", subtitle: "Chest link", icon: "scope", color: AppTheme.palette[2].color, package: "AimBody.3105", state: $aimBodyEnabled)
            compactPatchButton(title: "BODY", subtitle: "Body link", icon: "viewfinder", color: AppTheme.palette[4].color, package: "HSSLA.3105", state: $hsslaEnabled)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.accent.opacity(0.30), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }

    private func compactPatchButton(title: String, subtitle: String, icon: String, color: Color, package: String, state: Binding<Bool>) -> some View {
        Button {
            togglePatch(packageFilename: package, state: state)
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(state.wrappedValue ? color : color.opacity(0.38))
                    .frame(width: 4, height: 30)
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(state.wrappedValue ? color.opacity(0.18) : Color.white.opacity(0.05))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(state.wrappedValue ? color : color.opacity(0.88))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.8)
                    Text(state.wrappedValue ? "ACTIVE • LINKED TO CHARACTER" : subtitle.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.35)
                        .foregroundStyle(state.wrappedValue ? Color.black.opacity(0.68) : .white.opacity(0.42))
                }
                Spacer()
                Image(systemName: state.wrappedValue ? "checkmark" : "chevron.right")
                    .font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(state.wrappedValue ? Color.black : .white)
            .padding(.horizontal, 13)
            .frame(minHeight: 51)
            .background(state.wrappedValue ? color.opacity(0.92) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(state.wrappedValue ? color : Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: state.wrappedValue ? color.opacity(0.18) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(patchOperationBusy)
        .accessibilityLabel("Toggle \(title) patch")
    }

    private var enterGamePanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader(title: "ENTER GAME", detail: "READY", icon: "gamecontroller.fill")
            Text("Activate the patch buttons above, confirm the linked character region, then enter the selected game.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                launchButton(title: "ENTER NORMAL", subtitle: "Free Fire", color: AppTheme.accent, scheme: "freefireth")
                launchButton(title: "ENTER MAX", subtitle: "Free Fire Max", color: AppTheme.palette[6].color, scheme: "freefiremax")
            }
        }
        .padding(15)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.30), lineWidth: 1))
    }

    private var quickStartPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("QUICK START")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showQuickStart.toggle() }
                } label: {
                    Image(systemName: showQuickStart ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showQuickStart ? "Collapse quick start" : "Expand quick start")
            }
            if showQuickStart {
                Text("Choose a feature, confirm its state, then launch the supported game. Device-integrity checks remain visible before protected actions.")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    quickStartStep(number: "01", title: "CHECK", detail: "Review device")
                    quickStartStep(number: "02", title: "CHOOSE", detail: "Select a module")
                    quickStartStep(number: "03", title: "LAUNCH", detail: "Open your game")
                }
            }
        }
        .padding(15)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.18), lineWidth: 1))
    }

    private func quickStartStep(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var noKeyAccessPanel: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.green.opacity(0.13))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("TRY STORE LOCAL MODE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.42))
                Text("ACCESS ENABLED")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
                Text("Device-integrity review is still required for protected actions.")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.green.opacity(0.26), lineWidth: 1))
    }

    private var telemetryStrip: some View {
        HStack(spacing: 9) {
            telemetryCell(icon: "bolt.fill", label: "ACTIVE", value: "\(activePatchCount)/\(totalPatchCount)", color: activePatchCount > 0 ? .green : AppTheme.accent)
            telemetryCell(icon: "checkmark.seal.fill", label: "ACCESS", value: licenseGateEnabled ? (licenseManager.isActive ? "ACTIVE" : "LOCKED") : "LOCAL", color: licenseGateEnabled ? (licenseManager.isActive ? AppTheme.accent : .white.opacity(0.42)) : .green)
            telemetryCell(icon: "iphone", label: "DEVICE", value: appState.isSupported ? "VERIFIED" : "REVIEW", color: appState.isSupported ? .cyan : .red)
        }
    }

    private func telemetryCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private var sessionOverview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                panelHeader(title: "SESSION OVERVIEW", detail: sessionStateLabel, icon: "circle.grid.3x3.fill")
                Circle()
                    .fill(sessionStateColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: sessionStateColor, radius: 5)
            }

            if activeModules.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: licenseManager.isActive ? "sparkles" : "lock.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(sessionStateColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your loadout is clear")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Choose a module from Aim Options or Visual Options.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(activeModules) { module in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(module.color)
                                .frame(width: 7, height: 7)
                                .shadow(color: module.color, radius: 4)
                            Text(module.name)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(module.target)
                                .font(.system(size: 7, weight: .black, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(module.color.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(sessionStateColor.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            panelHeader(title: "DEVICE TELEMETRY", detail: "LIVE", icon: "waveform.path.ecg")
            HStack(spacing: 0) {
                statusRow(icon: "apple.logo", title: "iOS", value: AppInfo.osVersion, color: AppTheme.palette[2].color)
                statusDivider
                statusRow(icon: "iphone", title: "MODEL", value: AppInfo.displayMachineName, color: .cyan)
                statusDivider
                statusRow(icon: "lock.shield.fill", title: "INTEGRITY", value: appState.integrityStatus.isTrusted ? "TRUSTED" : "BLOCKED", color: appState.integrityStatus.isTrusted ? .green : .red)
            }
        }
        .padding(15)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 48)
    }

    private func statusRow(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.40))
            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var patchOptions: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PATCH CONSOLE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(AppTheme.accent)
                    Text("Each button links a live patch to the character")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer()
                                    Text("\(activePatchCount)/\(totalPatchCount) ACTIVE")

                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(activePatchCount > 0 ? .green : .white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background((activePatchCount > 0 ? Color.green : Color.white).opacity(0.10), in: Capsule())
            }

            patchSectionTabs
            gameFilterBar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.38))
                TextField("Search features", text: $patchSearchText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                if !patchSearchText.isEmpty {
                    Button { patchSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear feature search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            patchList

            HStack(spacing: 8) {
                Circle()
                    .fill(patchMessage.hasPrefix("SUCCESS") ? .green : AppTheme.accent)
                    .frame(width: 7, height: 7)
                Text(patchOperationBusy ? "PROCESSING PATCH…" : patchMessage)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.34), in: Capsule())
        }
    }

    private var patchSectionTabs: some View {
        HStack(spacing: 8) {
            ForEach(PatchSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedPatchSection = section
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 15, weight: .black))
                        Text(section.title)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(0.7)
                            .lineLimit(1)
                        Text(section.caption)
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .tracking(0.35)
                            .opacity(selectedPatchSection == section ? 0.62 : 0.36)
                    }
                    .foregroundStyle(selectedPatchSection == section ? Color.black : .white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background {
                        if selectedPatchSection == section {
                            LinearGradient(colors: [AppTheme.accent, AppTheme.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            Color.black.opacity(0.32)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(selectedPatchSection == section ? AppTheme.accent : Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(section.title.lowercased())")
                .accessibilityAddTraits(selectedPatchSection == section ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var gameFilterBar: some View {
        HStack(spacing: 7) {
            ForEach(GameFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedGameFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(selectedGameFilter == filter ? Color.black : .white.opacity(0.48))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selectedGameFilter == filter ? AppTheme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter patches by \(filter.title)")
                .accessibilityAddTraits(selectedGameFilter == filter ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.24), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func isVisible(target: String) -> Bool {
        selectedGameFilter.target == nil || selectedGameFilter.target == target
    }

    private func matches(_ name: String) -> Bool {
        patchSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || name.localizedCaseInsensitiveContains(patchSearchText)
    }

    @ViewBuilder
    private var patchList: some View {
        switch selectedPatchSection {
        case .aim:
            sectionLabel("AIM OPTIONS", icon: "scope")
            LazyVStack(spacing: 10) {
                if isVisible(target: "FREE FIRE NORMAL") && matches("MIRA ARRASTRE HS ALTO") { patchCard(name: "MIRA ARRASTRE HS ALTO✅", target: "FREE FIRE NORMAL", fileExcerpt: "cache_res…", package: "AimDragFreeFire.3105", color: AppTheme.accent, state: $aimDragEnabled) }
                if isVisible(target: "FREE FIRE NORMAL") && matches("MIRA CUELLO") { patchCard(name: "MIRA CUELLO", target: "FREE FIRE NORMAL", fileExcerpt: "cache_res…", package: "AimNeckFreeFire.3105", color: .cyan, state: $aimNeckEnabled) }
                if isVisible(target: "FREE FIRE MAX") && matches("HSLA") { patchCard(name: "HSLA", target: "FREE FIRE MAX", fileExcerpt: "assetindexer…", package: "HSSLA.3105", color: AppTheme.accent, state: $hsslaEnabled) }
                if isVisible(target: "FREE FIRE MAX") && matches("CUELLO SIN ANTENA") { patchCard(name: "CUELLO SIN ANTENA", target: "FREE FIRE MAX", fileExcerpt: "assetindexer…", package: "HSPESCOSEMANTENA.3105", color: AppTheme.palette[1].color, state: $hspEnabled) }
                if isVisible(target: "FREE FIRE MAX") && matches("HS PECHO HYPER") { patchCard(name: "HS PECHO HYPER", target: "FREE FIRE MAX", fileExcerpt: "cache_res…", package: "AimBody.3105", color: AppTheme.palette[4].color, state: $aimBodyEnabled) }
                if isVisible(target: "FREE FIRE NORMAL") && matches("HYPER BALAMÁGICA") { patchCard(name: "HYPER BALAMÁGICA", target: "FREE FIRE NORMAL", fileExcerpt: "cache_res…", package: "HYPERBALAMAGICA.3105", color: AppTheme.accent, state: $hyperBalamagicaEnabled) }
                if isVisible(target: "FREE FIRE NORMAL") && matches("AIMBOT PECHO") { patchCard(name: "AIMBOT PECHO", target: "FREE FIRE NORMAL", fileExcerpt: "assetindexer…", package: "AimbotPecho.3105", color: AppTheme.palette[2].color, state: $aimbotPechoEnabled) }
                if isVisible(target: "FREE FIRE MAX") && matches("AIMBOT PECHO MAX") { patchCard(name: "AIMBOT PECHO MAX", target: "FREE FIRE MAX", fileExcerpt: "assetindexer…", package: "AimbotPechoMax.3105", color: AppTheme.palette[2].color, state: $aimbotPechoMaxEnabled) }
            }
        case .visual:
            sectionLabel("VISUAL OPTIONS", icon: "eye.fill")
            LazyVStack(spacing: 10) {
                if isVisible(target: "FREE FIRE MAX") && matches("HOLOGRAMA ARMAS") { patchCard(name: "HOLOGRAMA ARMAS", target: "FREE FIRE MAX", fileExcerpt: "shaders…", package: "Shaders.3105", color: AppTheme.palette[5].color, state: $hologramaArmasEnabled) }
            }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.15)
            .foregroundStyle(.white.opacity(0.56))
            .padding(.top, 2)
    }

    private func patchCard(name: String, target: String, fileExcerpt: String, package: String, color: Color, state: Binding<Bool>) -> some View {
        PatchOptionCard(name: name, target: target, fileExcerpt: fileExcerpt, color: color, isEnabled: state, isBusy: patchOperationBusy, isCompact: compactPatchRows, showFileExcerpt: showFileFragments) {
            togglePatch(packageFilename: package, state: state)
        }
    }

    private var viewControlsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showViewControls.toggle()
                }
            } label: {
                HStack {
                    panelHeader(title: "PRESENTATION", detail: showViewControls ? "HIDE" : "CUSTOMIZE", icon: "paintbrush.pointed.fill")
                    Image(systemName: showViewControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize presentation")

            if showViewControls {
                VStack(spacing: 0) {
                    presentationToggle(title: "Compact patch rows", detail: "Fit more modules on screen", isOn: $compactPatchRows)
                    Divider().overlay(Color.white.opacity(0.08))
                    presentationToggle(title: "Show file fragments", detail: "Display short payload names", isOn: $showFileFragments)
                    Divider().overlay(Color.white.opacity(0.08))
                    presentationToggle(title: "Haptic feedback", detail: "Vibrate on protected actions", isOn: $hapticsEnabled)
                }
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(15)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func presentationToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .tint(AppTheme.accent)
        .padding(.vertical, 10)
        .accessibilityLabel(title)
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showAppearance.toggle()
                }
            } label: {
                HStack {
                    panelHeader(title: "APPEARANCE", detail: AppTheme.selectedAccent.name, icon: "paintpalette.fill")
                    Image(systemName: showAppearance ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showAppearance ? "Hide appearance colors" : "Show appearance colors")

            if showAppearance {
                HStack {
                    Text("20 COLORS / SAVED ON DEVICE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.75)
                        .foregroundStyle(.white.opacity(0.42))
                    Spacer()
                    Button("RESET GOLD") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            accentIndex = AppTheme.defaultAccentIndex
                        }
                    }
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset appearance to gold")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                    ForEach(AppTheme.palette) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                accentIndex = option.id
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: option.color.opacity(0.42), radius: accentIndex == option.id ? 8 : 2)
                                if accentIndex == option.id {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(option.id == 16 || option.id == 17 ? .black : .white)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(option.name)")
                        .accessibilityAddTraits(accentIndex == option.id ? .isSelected : [])
                    }
                }
            }
        }
        .padding(15)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.18), lineWidth: 1))
    }

    private var supportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "SUPPORT CENTER", detail: "24/7 CONTACT", icon: "person.2.fill")
            Text("Need help with TryStore?? Contact TryStore directly from the app.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://t.me/+EdvrAFwQbyg2ZDFh")!) {
                supportLinkLabel(title: "TryStore IOS GROUP", detail: "Join the Telegram support group", icon: "person.3.fill", color: .cyan)
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://www.instagram.com/guillenrmarcos?stkn=MTdqMGo2d200YmF3Yg%3D%3D&utm_source=qr")!) {
                supportLinkLabel(title: "INSTAGRAM", detail: "@guillenrmarcos", icon: "camera.fill", color: Color(red: 0.84, green: 0.22, blue: 0.56))
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func supportLinkLabel(title: String, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white.opacity(0.30))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(color.opacity(0.23), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var utilityPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            panelHeader(title: "QUICK ACTIONS", detail: "TOOLS", icon: "square.grid.2x2.fill")
            HStack(spacing: 10) {
                launchButton(title: "FF NORMAL", subtitle: "Free Fire", color: AppTheme.accent, scheme: "freefireth")
                launchButton(title: "FF MAX", subtitle: "Free Fire Max", color: AppTheme.palette[6].color, scheme: "freefiremax")
            }

            Button {
                removeTraces()
            } label: {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: removeTracesBusy ? "hourglass" : "trash.slash.fill")
                            .font(.system(size: 15, weight: .black))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(removeTracesBusy ? "REMOVING TRACES…" : "REMOVE TRACES")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.9)
                        Text("FREE FIRE NORMAL + FREE FIRE MAX")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .foregroundStyle(removeTracesBusy ? .white.opacity(0.45) : AppTheme.accent)
                .padding(.horizontal, 13)
                .frame(minHeight: 58)
                .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(AppTheme.accent.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(removeTracesBusy)
            .accessibilityLabel("Remove app-owned traces from Free Fire Normal and Free Fire MAX")
        }
        .padding(15)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func panelHeader(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white)
            Spacer()
            Text(detail)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func launchButton(title: String, subtitle: String, color: Color, scheme: String) -> some View {
        Button { openGame(scheme: scheme) } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(color.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Launch \(title): \(subtitle)")
    }

    private var socialLinksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(AppTheme.accent)
                Text("FOLLOW TRYSTORE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.25)
                    .foregroundStyle(.white)
                Spacer()
                Text("OFFICIAL LINKS")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.34))
            }

            HStack(spacing: 10) {
                socialLinkCard(
                    title: "TikTok",
                    handle: "@vaal_goat",
                    icon: "music.note",
                    colors: [Color.black, Color(red: 0.12, green: 0.08, blue: 0.22)],
                    url: "https://www.tiktok.com/@vaal_goat?_r=1&_t=ZS-99VyqChfs9J"
                )
                socialLinkCard(
                    title: "Instagram",
                    handle: "@guillenrmarcos",
                    icon: "camera.fill",
                    colors: [Color(red: 0.35, green: 0.06, blue: 0.28), Color(red: 0.08, green: 0.14, blue: 0.38)],
                    url: "https://www.instagram.com/guillenrmarcos?stkn=MTdqMGo2d200YmF3Yg%3D%3D&utm_source=qr"
                )
            }
        }
        .padding(15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 16, y: 8)
    }

    private func socialLinkCard(title: String, handle: String, icon: String, colors: [Color], url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.13))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.white)
                Text(handle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open TryStore \(title) profile \(handle)")
    }

    private var creditsPanel: some View {
        VStack(spacing: 10) {
            Text("DEVELOPMENT CREDITS")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
            HStack(spacing: 10) {
                AppLogo(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TryStore")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                    Text("Developed by Jvztxn • TryStore")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 0)
                Image(systemName: "signature")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(AppTheme.accent.opacity(0.75))
            }
            .padding(12)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(AppTheme.accent.opacity(0.16), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Development credits: Developed by Jvztxn and TryStore")
    }

    private var footerBar: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green, radius: 5)
            Text("SYSTEM READY")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text("DEVELOPED BY JVZTXN + TRYSTORE")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(AppTheme.accent.opacity(0.82))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.18), lineWidth: 1))
    }

    private func removeTraces() {
        guard !removeTracesBusy else { return }
        removeTracesBusy = true
        let bundleIDs = ["com.dts.freefireth", "com.dts.freefiremax"]
        DispatchQueue.global(qos: .userInitiated).async {
            var freedBytes: Int64 = 0
            var cleanedApps = 0
            var failures = 0
            for bundleID in bundleIDs {
                guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else { continue }
                do {
                    let result = try LimitedCleanerService.clean(
                        containerURL: URL(fileURLWithPath: containerPath, isDirectory: true),
                        rootValidator: { ContainerStore.isApplicationContainerPath($0.path) }
                    )
                    freedBytes += result.freedBytes
                    cleanedApps += 1
                    failures += result.failedItemCount
                } catch {
                    failures += 1
                    log("cleaner: Remove Traces failed for target app error=\(error)")
                }
            }
            DispatchQueue.main.async {
                self.removeTracesBusy = false
                if cleanedApps == 0 {
                    self.patchMessage = "REMOVE TRACES — TARGET APPS NOT AVAILABLE"
                } else if failures > 0 {
                    self.patchMessage = "REMOVE TRACES — PARTIAL CLEANUP"
                } else {
                    self.patchMessage = "REMOVE TRACES — \(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)) CLEARED"
                }
            }
        }
    }

    private func enforceLicenseExpiry() {
        guard licenseGateEnabled,
              !licenseManager.isActive,
              !licenseManager.isBusy,
              !patchOperationBusy,
              !expiryRestoreCompleted else { return }
        let hasActivePatch = activePatchCount > 0 || [
            "AimDragFreeFire.3105", "AimNeckFreeFire.3105", "HSSLA.3105",
            "HSPESCOSEMANTENA.3105", "AimBody.3105", "HYPERBALAMAGICA.3105", "AimbotPecho.3105", "AimbotPechoMax.3105", "Shaders.3105"
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
            "AimDragFreeFire.3105", "AimNeckFreeFire.3105", "HSSLA.3105",
            "HSPESCOSEMANTENA.3105", "AimBody.3105", "HYPERBALAMAGICA.3105", "AimbotPecho.3105", "AimbotPechoMax.3105", "Shaders.3105"
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
                self.patchMessage = restored > 0 ? "LICENSE EXPIRED — ORIGINALS RESTORED" : "LICENSE EXPIRED — NO ACTIVE PATCHES"
            }
        }
    }

    private func syncPatchStates() {
        aimDragEnabled = isPatchActive("AimDragFreeFire.3105")
        aimNeckEnabled = isPatchActive("AimNeckFreeFire.3105")
        hsslaEnabled = isPatchActive("HSSLA.3105")
        hspEnabled = isPatchActive("HSPESCOSEMANTENA.3105")
        aimBodyEnabled = isPatchActive("AimBody.3105")
        hyperBalamagicaEnabled = isPatchActive("HYPERBALAMAGICA.3105")
        aimbotPechoEnabled = isPatchActive("AimbotPecho.3105")
        aimbotPechoMaxEnabled = isPatchActive("AimbotPechoMax.3105")
        hologramaArmasEnabled = isPatchActive("Shaders.3105")
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
        case "AimDragFreeFire.3105": aimDragEnabled = enabled
        case "AimNeckFreeFire.3105": aimNeckEnabled = enabled
        case "HSSLA.3105": hsslaEnabled = enabled
        case "HSPESCOSEMANTENA.3105": hspEnabled = enabled
        case "AimBody.3105": aimBodyEnabled = enabled
        case "HYPERBALAMAGICA.3105": hyperBalamagicaEnabled = enabled
        case "AimbotPecho.3105": aimbotPechoEnabled = enabled
        case "AimbotPechoMax.3105": aimbotPechoMaxEnabled = enabled
        case "Shaders.3105": hologramaArmasEnabled = enabled
        default: break
        }
    }

    private func togglePatch(packageFilename: String, state: Binding<Bool>) {
        guard !patchOperationBusy else { return }
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
                            self.patchMessage = "OFF — NO ACTIVE PATCH FOUND"
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
                    case .restored:
                        self.setPatchState(for: packageFilename, enabled: false)
                        self.patchMessage = "SUCCESS — BYPASS DEACTIVATED"
                        PatchAudioFeedback.originalRestored()
                    case .unavailable(let message):
                        self.patchMessage = message
                    }
                    self.patchOperationBusy = false
                }
            }
        }
    }

    private func openGame(scheme: String) {
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
                    Text(isEnabled ? "PATCH ACTIVE" : "TAP TO ACTIVATE")
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
    private static let synthesizer = AVSpeechSynthesizer()
    private static var activationPlayer: AVAudioPlayer?
    private static var deactivationPlayer: AVAudioPlayer?

    static func bypassActivated() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? session.setActive(true, options: [])

        guard let url = Bundle.main.url(forResource: "PatchActivated", withExtension: "mp3") else {
            speak("Bypass activated")
            return
        }

        do {
            activationPlayer = try AVAudioPlayer(contentsOf: url)
            activationPlayer?.prepareToPlay()
            activationPlayer?.play()
        } catch {
            log("audio: activation sound unavailable: \(error)")
            speak("Bypass activated")
        }
    }

    static func originalRestored() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? session.setActive(true, options: [])

        guard let url = Bundle.main.url(forResource: "PatchDeactivated", withExtension: "mp3") else {
            speak("Bypass deactivated")
            return
        }

        do {
            deactivationPlayer = try AVAudioPlayer(contentsOf: url)
            deactivationPlayer?.prepareToPlay()
            deactivationPlayer?.play()
        } catch {
            log("audio: deactivation sound unavailable: \(error)")
            speak("Bypass deactivated")
        }
    }

    private static func speak(_ message: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        utterance.voice = voices.first(where: {
            $0.language.hasPrefix("en-US") && $0.gender == .female && $0.quality == .enhanced
        }) ?? voices.first(where: {
            $0.language.hasPrefix("en-US") && $0.gender == .female
        }) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.43
        utterance.pitchMultiplier = 1.10
        utterance.volume = 0.90
        synthesizer.speak(utterance)
    }
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
                    .opacity(0.16)
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
                ParticleField()
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
            for index in 0..<34 {
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
            TimelineView(.periodic(from: Date(), by: 0.05)) { timeline in
                fallingCanvas(time: timeline.date.timeIntervalSinceReferenceDate, size: proxy.size)
            }
        }
    }

    private func fallingCanvas(time: TimeInterval, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let width = max(canvasSize.width, size.width)
            let height = max(canvasSize.height, size.height)
            for index in 0..<44 {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AnimatedAtmosphere: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: Date(), by: 0.05)) { timeline in
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
                .blur(radius: 72)
                .offset(x: -size.width * 0.34 + driftX, y: -size.height * 0.30 + driftY)
            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 270, height: 270)
                .blur(radius: 76)
                .offset(x: size.width * 0.34 - driftX, y: size.height * 0.18 - driftY)
            Circle()
                .fill(AppTheme.accent.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
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
