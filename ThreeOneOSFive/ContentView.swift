import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        DashboardView()
            .tint(AppTheme.accent)
            .imageScale(.small)
            .preferredColorScheme(.dark)
    }
}

// MARK: - DashboardView
private enum DashboardPatchTab: String, CaseIterable, Identifiable {
    case loadout
    case visuals

    var id: String { rawValue }
    var title: String { self == .loadout ? "LOADOUT" : "VISUALS" }
    var icon: String { self == .loadout ? "scope" : "sparkles" }
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
        DashboardPatchOption(projectName: "Silent Aim", title: "ESP TRY", icon: "viewfinder", color: .mint, group: nil)
    ]

    static let visuals = [
        DashboardPatchOption(projectName: "HOLOGRAMA ARMAS", title: "HOLOGRAMA ARMAS", icon: "sparkles", color: .purple, group: nil),
        DashboardPatchOption(projectName: "HOLOGRAMA PERSONAJE", title: "HOLOGRAMA PERSONAJE", icon: "person.crop.circle.badge.sparkles", color: .pink, group: nil)
    ]

    static var all: [DashboardPatchOption] { loadout + visuals }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @StateObject private var patchStore = PatchProjectStore(game: .max)
    @State private var selectedPatchTab: DashboardPatchTab = .loadout
    @State private var showSettings = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            ZStack {
                TryStoreAmbientBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        topBar
                        heroPanel
                        telemetryStrip
                        legacyPatchPanel
                        deviceSection
                        quickStartPanel
                        characterPreviewPanel
                        socialLinksPanel
                        footerBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
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
                Text("SECURE EDITION")
                    .font(.system(size: horizontalSizeClass == .compact ? 7 : 9, weight: .black, design: .rounded))
                    .tracking(horizontalSizeClass == .compact ? 0.8 : 1.15)
                    .foregroundStyle(AppTheme.accent)
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
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: horizontalSizeClass == .compact ? 34 : 40, height: horizontalSizeClass == .compact ? 34 : 40)
                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            Image("CleanCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 164, height: 210)
                .opacity(0.92)
                .offset(x: 5, y: 11)
                .mask(LinearGradient(colors: [.white, .white.opacity(0.92), .clear], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 10) {
                Text("TRY STORE / CONTROL DECK")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.35)
                    .foregroundStyle(AppTheme.accent)
                Text("Patch smarter.\nPlay cleaner.")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your classic blue TryStore interface, focused on Free Fire MAX.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    heroBadge(icon: "gamecontroller.fill", title: "MAX ONLY")
                    heroBadge(icon: "sparkles", title: "SIGNATURE BLUE")
                }
            }
            .padding(17)
            .padding(.trailing, 112)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(minHeight: 208)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AppTheme.accent.opacity(0.40), lineWidth: 1))
        .shadow(color: AppTheme.accent.opacity(0.11), radius: 20, y: 9)
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
            panelHeader(title: "DEVICE OVERVIEW", subtitle: "LIVE SYSTEM STATUS", icon: "iphone.gen3")
            statusRow(title: language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
            statusRow(title: language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
            HStack {
                Text(language.text("settings.exploit_compatibility"))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text(language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"))
                    .fontWeight(.bold)
                    .foregroundStyle(appState.isSupported ? .green : .orange)
            }
            .font(.system(size: 10, design: .rounded))
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
        .background(AppTheme.consoleBackground.opacity(0.90), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(AppTheme.accent.opacity(0.17), lineWidth: 1))
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
                    .shadow(color: AppTheme.accent.opacity(0.24), radius: 18, y: 6)
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
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(AppTheme.accent.opacity(0.25), lineWidth: 1))
            Text("The original TryStore character and signature-blue look are back.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
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
                    Text("\(activeLegacyPatchCount) / 7 ON")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }

            HStack(spacing: 7) {
                ForEach(DashboardPatchTab.allCases) { tab in
                    let selected = selectedPatchTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedPatchTab = tab
                        }
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(0.55)
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.58))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                selected ? AppTheme.accent.opacity(0.28) : Color.white.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? AppTheme.accent.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            if selectedPatchTab == .visuals {
                visualPatchPreview
            } else {
                Text("Tap a patch to turn it on; tap the same button again to restore the original.")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 7) {
                ForEach(selectedPatchTab == .loadout ? DashboardPatchOption.loadout : DashboardPatchOption.visuals) { option in
                    legacyPatchButton(option)
                }
            }

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
                colors: [Color(red: 0.035, green: 0.12, blue: 0.24), AppTheme.consoleBackground.opacity(0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(AppTheme.accent.opacity(0.32), lineWidth: 1))
        .shadow(color: AppTheme.accent.opacity(0.08), radius: 16, y: 7)
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
        let item = patchStore.items.first {
            $0.project?.name == option.projectName
                || $0.packageURL.lastPathComponent.caseInsensitiveCompare("\(option.projectName).3105") == .orderedSame
        }
        let isActive = item.map { DevicePatchService.latestReceipt(projectID: $0.id) != nil } ?? false

        return Button {
            guard let item else { return }
            patchStore.setEnabled(!isActive, for: item, group: option.group, reportsSuccess: false)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(isActive ? .white : option.color)
                    .frame(width: 34, height: 34)
                    .background(
                        (isActive ? option.color : option.color.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(.white)
                    Text("FREE FIRE MAX PATCH")
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .tracking(0.55)
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 4)
                Text(item == nil ? "MISSING" : (isActive ? "ON" : "OFF"))
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(item == nil ? .orange : (isActive ? .white : .white.opacity(0.48)))
                    .frame(minWidth: 39, minHeight: 23)
                    .background(
                        isActive ? option.color.opacity(0.42) : Color.white.opacity(0.055),
                        in: Capsule()
                    )
                Image(systemName: item == nil ? "exclamationmark.triangle.fill" : (isActive ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(item == nil ? .orange : (isActive ? option.color : .white.opacity(0.30)))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background(
                isActive ? option.color.opacity(0.15) : Color.white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? option.color.opacity(0.58) : Color.white.opacity(0.075), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(patchStore.isBusy || item == nil)
        .opacity(patchStore.isBusy ? 0.72 : (item == nil ? 0.52 : 1))
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
        HStack(spacing: 7) {
            Image(systemName: "bolt.shield.fill")
                .foregroundStyle(AppTheme.accent)
            Text("TRY STORE  •  SIGNATURE BLUE  •  FREE FIRE MAX")
                .foregroundStyle(.white.opacity(0.40))
        }
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.55)
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
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

private struct TryStoreAmbientBackground: View {
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
                .offset(x: 145, y: -300)
            Circle()
                .fill(Color.blue.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 68)
                .offset(x: -130, y: 250)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO", "Silent Aim"]
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
        case "Silent Aim": return "ESP TRY"
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
                Text("Bundled MAX catalog · live patch status")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
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
                    patchHeroPanel
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
                                Toggle(isOn: Binding(
                                    get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                    set: { store.setEnabled($0, for: item, group: .aim) }
                                )) {
                                    Label(aimDisplayName(for: item), systemImage: "scope")
                                        .foregroundStyle(.white)
                                }
                                .tint(AppTheme.accent)
                                .padding(12)
                                .background(AppTheme.consoleBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AppTheme.accent.opacity(0.17), lineWidth: 1))
                                .disabled(store.isBusy)
                            }
                        } else {
                            if locationItems.isEmpty {
                                emptyPatchNotice
                            }
                            ForEach(locationItems) { item in
                                Toggle(isOn: Binding(
                                    get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                    set: { store.setEnabled($0, for: item, group: .location) }
                                )) {
                                    Label(locationDisplayName(for: item), systemImage: "location.fill")
                                        .foregroundStyle(.white)
                                }
                                .tint(AppTheme.accent)
                                .padding(12)
                                .background(AppTheme.consoleBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AppTheme.accent.opacity(0.17), lineWidth: 1))
                                .disabled(store.isBusy)
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
        // Chỉ tải một lần (dùng static flag)
        guard !Self.loadedGames.contains(game) else {
            // Nếu đã tải, chỉ cần reload store và tắt loading
            await MainActor.run {
                store.reload()
                isLoading = false
            }
            return
        }

        // Bắt đầu loading
        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        // Chạy tác vụ nặng trong background
        await Task.detached(priority: .userInitiated) {
            do {
                // Gọi các hàm install (có thể là đồng bộ, nhưng chạy ở background)
                // Nếu các hàm này throw, catch sẽ bắt
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        // Thực hiện cài đặt
                        for patch in game.bundledPatches {
                            if patch.resourceName.hasSuffix(".3105") {
                                PatchProjectLibrary.installBundledFileIfNeeded(
                                    filename: patch.resourceName,
                                    projectName: patch.projectName,
                                    password: patch.password
                                )
                            } else {
                                PatchProjectLibrary.installBundledPackageIfNeeded(
                                    resourceName: patch.resourceName,
                                    projectName: patch.projectName,
                                    password: patch.password
                                )
                            }
                        }

                        // Sau khi cài xong, reload store
                        DispatchQueue.main.async {
                            store.reload()
                            // Đánh dấu đã load
                            Self.loadedGames.insert(game)
                            continuation.resume()
                        }
                    }
                }
                // Cập nhật UI: tắt loading
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load patches: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }.value // chờ task hoàn thành
    }

    // Static flag để chỉ load một lần
    private static var loadedGames: Set<FreeFireGame> = []
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
