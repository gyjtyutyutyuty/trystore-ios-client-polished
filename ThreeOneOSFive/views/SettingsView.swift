import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage("jvztxnx.compactPatchRows") private var compactPatchRows = false
    @AppStorage("jvztxnx.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("jvztxnx.expirationReminders") private var expirationReminders = true
    @AppStorage("jvztxnx.updateNotices") private var updateNotices = true
    @AppStorage("jvztxnx.themeMode") private var themeMode = "dark"
    @State private var diagnosticsCopied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("TryStore").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Compact feature rows", isOn: $compactPatchRows)
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    Picker("Theme", selection: $themeMode) {
                        Text("TryStore Dark").tag("dark")
                        Text("Dark · High contrast").tag("contrast")
                    }
                    LabeledContent("Theme", value: themeMode == "contrast" ? "High contrast" : "TryStore Dark")
                    Text("Accent colors can be changed from the Appearance panel on the home screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Expiration reminders", isOn: $expirationReminders)
                    Toggle("Update notices", isOn: $updateNotices)
                }

                Section {
                    Link(destination: URL(string: "https://t.me/jvztxn")!) {
                        Label("Contact support on Telegram", systemImage: "paperplane.fill")
                    }
                    Link(destination: URL(string: "https://wa.me/13214970363")!) {
                        Label("Contact support on WhatsApp", systemImage: "message.fill")
                    }
                    NavigationLink {
                        ClientDiagnosticsView()
                    } label: {
                        Label("Activity & diagnostics", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink {
                        ClientHelpView()
                    } label: {
                        Label("Troubleshooting guide", systemImage: "questionmark.circle")
                    }
                    Button {
                        UIPasteboard.general.string = supportDiagnostics
                        diagnosticsCopied = true
                    } label: {
                        Label(diagnosticsCopied ? "Diagnostics copied" : "Copy support diagnostics", systemImage: diagnosticsCopied ? "checkmark.circle" : "doc.on.doc")
                    }
                }

                Section {
                    Text("TryStore local access mode is enabled for this build. Device integrity remains checked separately before protected actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Device integrity", value: appState.integrityStatus.label)
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

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS 27.0")
                            .font(.body)
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                            Text(versionLabel(version))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }

            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var supportDiagnostics: String {
        "TryStore Support Diagnostics\\nApp: \(appVersion)\\niOS: \(AppInfo.osVersion) (\(AppInfo.osBuild))\\nDevice: \(AppInfo.displayMachineName)\\nAccess: LOCAL MODE\\nIntegrity: \(appState.integrityStatus.label)"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func versionLabel(
        _ version: (beta: Int, publicBeta: Int?, build: String)
    ) -> String {
        if let publicBeta = version.publicBeta {
            return language.text(
                "settings.developer_public_beta_build",
                Int64(version.beta),
                Int64(publicBeta),
                version.build
            )
        }
        return language.text(
            "settings.developer_beta_build",
            Int64(version.beta),
            version.build
        )
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


struct ClientDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var copied = false

    private var safeReport: String {
        "TryStore Diagnostics\\nApp: \(appVersion)\\niOS: \(AppInfo.osVersion) (\(AppInfo.osBuild))\\nDevice: \(AppInfo.displayMachineName)\\nAccess: LOCAL MODE\\nIntegrity: \(appState.integrityStatus.label)"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Access", value: "Local mode")
                LabeledContent("Integrity", value: appState.integrityStatus.label)
            } header: {
                Text("Current status")
            }
            Section {
                LabeledContent("App version", value: appVersion)
                LabeledContent("iOS", value: "\\(AppInfo.osVersion) (\\(AppInfo.osBuild))")
                LabeledContent("Model", value: AppInfo.displayMachineName)
            } header: {
                Text("Device")
            }
            Section {
                Button {
                    UIPasteboard.general.string = safeReport
                    copied = true
                } label: {
                    Label(copied ? "Safe diagnostics copied" : "Copy safe diagnostics", systemImage: copied ? "checkmark.circle" : "doc.on.doc")
                }
                Text("This report excludes private file paths and raw application logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Support")
            }
        }
        .tint(AppTheme.accent)
        .navigationTitle("Activity & diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }
}

struct ClientHelpView: View {
    var body: some View {
        List {
            Section("Local access") {
                Text("This build uses local access mode. Device integrity is still checked before protected actions.")
            }
            Section("Integrity") {
                Text("Integrity is a separate device and app-environment check. The app shows REVIEW REQUIRED when the installation or device environment does not meet the security policy.")
            }
            Section("Need help?") {
                Text("Contact support from the Support section and include the app version, iOS version, and the visible integrity message.")
            }
        }
        .tint(AppTheme.accent)
        .navigationTitle("Help & troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
    }
}
