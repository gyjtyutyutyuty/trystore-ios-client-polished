import SwiftUI

struct LogView: View {
    @ObservedObject var appLog = AppLog.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var copied = false

    /// A console reads faster when the eye can find the failure without
    /// reading every line. The rail is the only colour on the row.
    private func severityTint(_ entry: String) -> Color {
        let line = entry.lowercased()
        if line.contains("fail") || line.contains("error") || line.contains("denied") {
            return AppPalette.coral
        }
        if line.contains("warn") || line.contains("retry") {
            return AppPalette.amber
        }
        return AppPalette.brand.opacity(0.55)
    }

    private var shareText: String {
        var lines: [String] = []
        lines.append("Support Patch Log")
        lines.append("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) — \(AppInfo.machineName)")
        lines.append("Generated: \(Date())")
        lines.append("")
        lines.append(contentsOf: appLog.entries)
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                Group {
                if appLog.entries.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "apple.terminal")
                            .font(.system(size: AppTheme.emptyIconSize, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(language.text("logs.empty_title"))
                            .font(.title3.bold())
                        Text(language.text("logs.empty_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(appLog.entries.enumerated()), id: \.offset) { index, entry in
                                    HStack(alignment: .top, spacing: AppSpacing.m) {
                                        Capsule()
                                            .fill(severityTint(entry))
                                            .frame(width: 2)
                                            .padding(.vertical, 1)

                                        Text(entry)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(AppPalette.textSecondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, AppSpacing.m)
                                    .background(index.isMultiple(of: 2) ? Color.clear : AppPalette.raised.opacity(0.28))
                                    .id(index)
                                    .accessibilityLabel(language.text("accessibility.log_entry", Int64(index + 1), entry))
                                }
                            }
                            .padding(AppTheme.pageInset)
                            .background(AppTheme.consoleBackground)
                        }
                        .onChange(of: appLog.entries.count) { count in
                            guard count > 0 else { return }
                            if reduceMotion {
                                proxy.scrollTo(count - 1, anchor: .bottom)
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(count - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                }
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
            .appCinematicReveal(delay: 0.04)
            .appDepthLayer(.card)
            .navigationTitle(language.text("logs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(language.text("logs.clear"), role: .destructive) { appLog.entries.removeAll() }
                        .disabled(appLog.entries.isEmpty)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = shareText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(appLog.entries.isEmpty)
                    .accessibilityLabel(language.text("logs.copy"))

                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(appLog.entries.isEmpty)
                    .accessibilityLabel(language.text("logs.share"))

                    Button(language.text("common.done")) {
                        AppHaptics.tap()
                        dismiss()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
