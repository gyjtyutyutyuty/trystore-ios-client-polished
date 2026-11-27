



import SwiftUI
import Darwin
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage("settings_reduce_motion_enabled") private var reduceMotionEnabled = false
    @State private var isLicenseForgetConfirmationPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("TRY STORE").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                }

                Section(language.text("settings.stats_overlay")) {
                    Toggle(language.text("settings.stats_overlay_toggle"), isOn: $appState.showStatsOverlay)
                        .labelsHidden()
                    if appState.showStatsOverlay {
                        LabeledContent("System thermal state", value: appState.thermalStateLabel)
                        Text("iOS does not expose raw CPU/GPU temperatures in °C to apps.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LabeledContent(language.text("dashboard.launch_count"), value: "\(appState.totalLaunches)")
                    }
                }

                Section(language.text("settings.reduce_motion")) {
                    Toggle(language.text("settings.reduce_motion_toggle"), isOn: $reduceMotionEnabled)
                        .labelsHidden()
                }

                Section(language.text("license.settings_section")) {
                    LabeledContent(
                        language.text("license.settings_status"),
                        value: language.text(licenseManager.isActive ? "license.settings_active" : "license.settings_required")
                    )
                    if let expirationDate = licenseManager.expirationDate {
                        LabeledContent(
                            language.text("license.settings_expiration"),
                            value: expirationDate.formatted(date: .complete, time: .complete)
                        )
                    }
                    if let maskedKey = licenseManager.maskedKey {
                        LabeledContent(language.text("license.settings_key"), value: maskedKey)
                    }
                    if let messageKey = licenseManager.messageKey {
                        Text(language.text(messageKey))
                            .font(.footnote)
                            .foregroundStyle(licenseManager.isOffline ? .orange : .secondary)
                    }
                    Button {
                        licenseManager.refresh()
                    } label: {
                        Label(language.text("license.settings_verify"), systemImage: "arrow.clockwise")
                    }
                    .disabled(licenseManager.isBusy)
                    Button(role: .destructive) {
                        isLicenseForgetConfirmationPresented = true
                    } label: {
                        Text(language.text("license.settings_forget"))
                    }
                }

                Section {
                    HStack {
                        Text(language.text("settings.exploit_compatibility"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"))
                            .foregroundStyle(appState.isSupported ? Color.green : Color.orange)
                    }
                    ForEach(ExploitSupportPolicy.supportedMajorVersions, id: \.self) { major in
                        DisclosureGroup("iOS \(major)") {
                            ForEach(ExploitSupportPolicy.verifiedVersions.filter { $0.major == major }) { version in
                                LabeledContent("iOS \(version.version)") {
                                    Text(version.builds.joined(separator: ", "))
                                        .font(.caption.monospaced())
                                        .multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }
                Section(language.text("ffhub.section")) {
                    panelRow(
                        name: language.text("ffhub.title"),
                        role: language.text("ffhub.subtitle")
                    )
                }
                Section(language.text("settings.developer")) {
                    creditsRow(
                        name: language.text("developer.attribution"),
                        role: language.text("developer.telegram"),
                        url: "https://t.me/Jvztxn"
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(AppPremiumBackdrop())
            .appCinematicReveal(delay: 0.05)
            .appDepthLayer(.card)
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) {
                        AppHaptics.tap()
                        dismiss()
                    }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                language.text("license.forget_title"),
                isPresented: $isLicenseForgetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(language.text("license.forget_action"), role: .destructive) {
                    licenseManager.clear()
                }
                Button(language.text("license.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("license.forget_message"))
            }
        }
    }





    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private static let panelURL = URL(string: "https://ffhub-outfit-panel-nzvoam.freebuff.site")!

    /// The panel is private, so it is opened with a one-shot token minted for
    /// this device. Without one there is nothing to open but the login screen,
    /// which is where a broken attestation lands instead of a dead row.
    private func panelRow(name: String, role: String) -> some View {
        Button {
            Task { await openPanel() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("accessibility.open_profile", name))
    }

    @MainActor
    private func openPanel() async {
        let fallback = Self.panelURL.appendingPathComponent("login")
        guard let token = await licenseManager.panelSessionToken(),
              var components = URLComponents(url: Self.panelURL, resolvingAgainstBaseURL: false) else {
            await UIApplication.shared.open(fallback)
            return
        }
        components.fragment = "t=\(token)"
        await UIApplication.shared.open(components.url ?? fallback)
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}


struct PairingDocumentPicker: UIViewControllerRepresentable {
    let onSelection: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelection: (URL) -> Void

        init(onSelection: @escaping (URL) -> Void) {
            self.onSelection = onSelection
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelection(url)
        }
    }
}


enum PairingFileImportError: Error {
    case invalidPropertyList
    case fileTooLarge
}

enum PairingFileStore {
    private static let maximumFileSize = 10 * 1_024 * 1_024

    private static var pairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aircard_pairing.plist")
    }

    static var isReady: Bool {
        guard let data = try? Data(contentsOf: pairingFileURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any] else {
            return false
        }
        return !dictionary.isEmpty
    }

    static func delete() throws {
        try FileManager.default.removeItem(at: pairingFileURL)
    }

    static func importFile(from sourceURL: URL) throws {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        guard data.count <= maximumFileSize else {
            throw PairingFileImportError.fileTooLarge
        }
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any],
              !dictionary.isEmpty else {
            throw PairingFileImportError.invalidPropertyList
        }

        try data.write(to: pairingFileURL, options: .atomic)
    }
}
