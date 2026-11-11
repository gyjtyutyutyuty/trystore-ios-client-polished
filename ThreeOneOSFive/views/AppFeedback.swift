import SwiftUI

// MARK: - Rolling readings

/// Numbers that change should move like a counter, not blink. `contentTransition`
/// is the real thing on iOS 17; earlier systems get the plain value so the
/// reading never lies about its own state.
struct AppRollingNumber: View {
    let value: Int
    var size: CGFloat = 22
    var tint: Color = AppPalette.brand

    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        content
            .font(AppType.digits(size))
            .monospacedDigit()
            .foregroundStyle(tint)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: value)
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 17.0, *) {
            Text("\(value)")
                .contentTransition(.numericText(value: Double(value)))
        } else {
            Text("\(value)")
        }
    }
}

// MARK: - Toast

struct AppToastMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    var icon: String
    var tint: Color

    init(text: String, icon: String = "checkmark.circle.fill", tint: Color = AppPalette.brand) {
        self.id = UUID()
        self.text = text
        self.icon = icon
        self.tint = tint
    }
}

extension View {
    /// A single line that answers the hand and then leaves. Confirmations that
    /// destroy something still use an alert; everything else uses this.
    func appToast(_ message: Binding<AppToastMessage?>) -> some View {
        modifier(AppToastModifier(message: message))
    }
}

private struct AppToastModifier: ViewModifier {
    @Binding var message: AppToastMessage?
    @Environment(\.appReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: message.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(message.tint)
                        Text(message.text)
                            .font(AppType.label().weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.vertical, AppSpacing.m)
                    .background(AppPalette.raised.opacity(0.96), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(message.tint.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8)
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.top, AppSpacing.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            self.message = nil
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: message)
    }
}

// MARK: - Transaction

struct PatchTransactionProgress: Identifiable, Equatable {
    enum Phase: Equatable {
        case running
        case success(String)
        case failure(String)
    }

    let id = UUID()
    let title: String
    var done: Int
    var total: Int
    var phase: Phase

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(done) / Double(total)))
    }
}

/// The patch transaction is the one operation where a spinner is not enough:
/// it writes into another app's container, verifies every digest and can roll
/// back. This overlay shows the count it is actually on and the result, and it
/// never claims a phase the transaction did not report.
struct PatchTransactionOverlay: View {
    let progress: PatchTransactionProgress
    var onClose: () -> Void

    @Environment(\.appLanguage) private var language
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            (reduceTransparency ? AppPalette.canvas.opacity(0.92) : Color.black.opacity(0.62))
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.l) {
                ring

                VStack(spacing: AppSpacing.xs) {
                    Text(progress.title)
                        .font(AppType.value())
                        .foregroundStyle(AppPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(language.text("patch.transaction.files", Int64(progress.done), Int64(progress.total)))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .monospacedDigit()
                }

                phaseRow

                if case .running = progress.phase {
                    EmptyView()
                } else {
                    Button(action: onClose) {
                        Text(language.text("common.done"))
                            .font(AppType.label().weight(.semibold))
                            .foregroundStyle(AppPalette.canvas)
                            .padding(.horizontal, AppSpacing.xl)
                            .frame(minHeight: 44)
                            .background(AppPalette.brand, in: Capsule())
                    }
                    .buttonStyle(AppPressButtonStyle())
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 320)
            .background(
                AppPalette.surface,
                in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .strokeBorder(AppPalette.hairline.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.5), radius: 30, y: 14)
        }
        .transition(.opacity)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(AppPalette.hairline.opacity(0.55), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(progress.fraction)))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress.fraction)
            Text("\(Int((progress.fraction * 100).rounded()))%")
                .font(AppType.digits(24))
                .foregroundStyle(AppPalette.textPrimary)
                .monospacedDigit()
        }
        .frame(width: 108, height: 108)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var phaseRow: some View {
        switch progress.phase {
        case .running:
            HStack(spacing: AppSpacing.s) {
                ProgressView()
                    .controlSize(.small)
                Text(language.text("patch.operation_in_progress"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(2)
            }
        case .success(let message):
            statusLine(icon: "checkmark.seal.fill", text: message, tint: AppPalette.mint)
        case .failure(let message):
            statusLine(icon: "xmark.octagon.fill", text: message, tint: AppPalette.coral)
        }
    }

    private func statusLine(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch progress.phase {
        case .running: return AppPalette.brand
        case .success: return AppPalette.mint
        case .failure: return AppPalette.coral
        }
    }
}
