import SwiftUI
import UIKit

struct AccessGateView: View {
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var appState: AppState
    @State private var keyInput = ""
    @State private var revealKey = false
    @State private var didLoadRememberedKey = false
    @FocusState private var keyFocused: Bool

    private var trimmedKey: String {
        keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusColor: Color {
        if licenseManager.isBusy { return AppTheme.accent }
        if licenseManager.message != nil { return licenseManager.isOffline ? .orange : .red }
        return AppTheme.accent
    }

    var body: some View {
        ZStack {
            accessBackdrop
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandHeader
                    accessCard
                    trustStrip
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !didLoadRememberedKey else { return }
            didLoadRememberedKey = true
            if licenseManager.rememberKey {
                keyInput = licenseManager.rememberedKey() ?? ""
            }
        }
    }

    private var accessBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.11),
                    Color(red: 0.008, green: 0.012, blue: 0.035),
                    AppTheme.pageBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.accent.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 75)
                .offset(x: 130, y: -300)

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 250, height: 250)
                .blur(radius: 80)
                .offset(x: -150, y: 300)

            AccessGrid()
                .stroke(Color.white.opacity(0.035), lineWidth: 1)
                .ignoresSafeArea()
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.50), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.24), radius: 24)
                AppLogo(size: 62)
            }

            VStack(spacing: 7) {
                Text("TRY STORE")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .tracking(3.4)
                    .foregroundStyle(.white)
                Text("SECURE ACCESS CONSOLE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 7) {
                Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                Text("PRIVATE PATCH ENVIRONMENT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
        .padding(.bottom, 28)
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: licenseManager.isBusy ? "arrow.triangle.2.circlepath" : "lock.open.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("PATCH ZONE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(AppTheme.accent)
                    Text("Unlock your workspace")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Enter your access key before opening the patch console.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            keyField

            HStack(spacing: 10) {
                Button {
                    licenseManager.setRememberKey(!licenseManager.rememberKey)
                } label: {
                    Image(systemName: licenseManager.rememberKey ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(licenseManager.rememberKey ? AppTheme.accent : .white.opacity(0.36))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(licenseManager.rememberKey ? "Stop remembering key" : "Remember key on this device")

                VStack(alignment: .leading, spacing: 3) {
                    Text("REMEMBER ON THIS DEVICE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Stored in the secure iOS Keychain")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.green.opacity(0.82))
            }

            Button {
                keyFocused = false
                licenseManager.activate(key: trimmedKey)
            } label: {
                HStack(spacing: 9) {
                    if licenseManager.isBusy {
                        ProgressView().tint(.black).scaleEffect(0.78)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(licenseManager.isBusy ? "VERIFYING ACCESS" : "ACTIVATE & ENTER")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.75)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(
                    trimmedKey.isEmpty || licenseManager.isBusy
                        ? AppTheme.accent.opacity(0.45)
                        : AppTheme.accent,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .shadow(color: AppTheme.accent.opacity(trimmedKey.isEmpty ? 0 : 0.30), radius: 16, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(trimmedKey.isEmpty || licenseManager.isBusy)

            if let message = licenseManager.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: licenseManager.isOffline ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(licenseManager.isOffline ? .orange : .red.opacity(0.92))
                .padding(.top, 1)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(statusColor.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 28, y: 14)
    }

    private var keyField: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)

            Group {
                if revealKey {
                    TextField("TRY-XXXX-XXXX-XXXX", text: $keyInput)
                } else {
                    SecureField("TRY-XXXX-XXXX-XXXX", text: $keyInput)
                }
            }
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .textContentType(.password)
            .submitLabel(.go)
            .focused($keyFocused)
            .onSubmit {
                guard !trimmedKey.isEmpty, !licenseManager.isBusy else { return }
                licenseManager.activate(key: trimmedKey)
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)

            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.40))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealKey ? "Hide key" : "Show key")
        }
        .padding(.horizontal, 13)
        .frame(height: 54)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(keyFocused ? AppTheme.accent : Color.white.opacity(0.12), lineWidth: keyFocused ? 1.4 : 1)
        )
    }

    private var trustStrip: some View {
        HStack(spacing: 0) {
            accessFact(icon: "lock.shield.fill", title: "KEYCHAIN", detail: "DEVICE-ONLY")
            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 34)
            accessFact(icon: "network.badge.shield.half.filled", title: "VERIFY", detail: "LIVE CHECK")
            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 34)
            accessFact(icon: appState.canUseProtectedFeatures ? "checkmark.circle.fill" : "exclamationmark.circle.fill", title: "DEVICE", detail: appState.canUseProtectedFeatures ? "READY" : "REVIEW")
        }
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.top, 14)
    }

    private func accessFact(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.42))
            Text(detail)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Text("ACCESS IS BOUND TO THIS DEVICE")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(AppTheme.accent.opacity(0.72))
            Text("Your key is never displayed in plain text unless you choose to reveal it.")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.30))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 22)
    }
}

private struct AccessGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 36
        stride(from: rect.minX, through: rect.maxX, by: spacing).forEach { x in
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        stride(from: rect.minY, through: rect.maxY, by: spacing).forEach { y in
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
EOF
cd /home/ubuntu/trystore-ios-client-polished && test -s ThreeOneOSFive/views/AccessGateView.swift && echo 'AccessGateView created'
