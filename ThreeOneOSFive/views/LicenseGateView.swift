import SwiftUI

struct LicenseGateView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var licenseManager: LicenseManager
    @State private var keyInput = ""
    @State private var revealKey = false
    @FocusState private var keyFocused: Bool

    private var statusTint: Color {
        if licenseManager.isBusy { return AppTheme.accent }
        if licenseManager.messageKey != nil { return licenseManager.isOffline ? .orange : .red }
        return AppTheme.accent
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.035, blue: 0.11), Color(red: 0.008, green: 0.012, blue: 0.035), AppTheme.pageBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.accent.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 78)
                .offset(x: 150, y: -320)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        AppLogo(size: 68)
                            .padding(12)
                            .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(AppTheme.accent.opacity(0.42), lineWidth: 1))
                        Text("TRY STORE")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .tracking(2.8)
                            .foregroundStyle(.white)
                        Text(language.text("license.gate_kicker"))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: licenseManager.isBusy ? "arrow.triangle.2.circlepath" : "key.fill")
                                .font(.system(size: 19, weight: .black))
                                .foregroundStyle(statusTint)
                                .frame(width: 44, height: 44)
                                .background(statusTint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(language.text("license.gate_title"))
                                    .font(.system(size: 21, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(language.text("license.gate_message"))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "key.horizontal.fill")
                                .foregroundStyle(AppTheme.accent)
                            Group {
                                if revealKey {
                                    TextField(language.text("license.key_placeholder"), text: $keyInput)
                                } else {
                                    SecureField(language.text("license.key_placeholder"), text: $keyInput)
                                }
                            }
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textContentType(.oneTimeCode)
                            .submitLabel(.go)
                            .focused($keyFocused)
                            .onSubmit { activate() }
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(language.text(revealKey ? "license.hide_key" : "license.show_key"))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(keyFocused ? AppTheme.accent : Color.white.opacity(0.12), lineWidth: 1))

                        Button(action: activate) {
                            HStack(spacing: 9) {
                                if licenseManager.isBusy {
                                    ProgressView().tint(.black).controlSize(.small)
                                } else {
                                    Image(systemName: "lock.open.fill")
                                }
                                Text(language.text(licenseManager.isBusy ? "license.verifying" : "license.activate"))
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .tracking(0.8)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(AppTheme.accent.opacity(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseManager.isBusy ? 0.48 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseManager.isBusy)

                        if let messageKey = licenseManager.messageKey {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: licenseManager.isOffline ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                                Text(language.text(messageKey))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(licenseManager.isOffline ? .orange : .red.opacity(0.92))
                        }

                        if licenseManager.hasSavedKey && !licenseManager.isBusy {
                            Button {
                                licenseManager.refresh()
                            } label: {
                                Label(language.text("license.retry"), systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(statusTint.opacity(0.30), lineWidth: 1))
                    .shadow(color: .black.opacity(0.32), radius: 24, y: 12)

                    HStack(spacing: 9) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green.opacity(0.85))
                        Text(language.text("license.keychain_note"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
            .appDepthLayer(.card)
        }
        .preferredColorScheme(.dark)
    }

    private func activate() {
        keyFocused = false
        licenseManager.activate(key: keyInput)
    }
}
