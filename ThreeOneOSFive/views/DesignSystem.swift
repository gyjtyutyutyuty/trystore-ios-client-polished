import SwiftUI

struct AppAccentOption: Identifiable {
    let id: Int
    let name: String
    let color: Color
}

enum AppTheme {
    static let accentStorageKey = "trystore.accentIndex"
    static let defaultAccentIndex = 19

    static let palette: [AppAccentOption] = [
        .init(id: 0, name: "ICE BLUE", color: Color(red: 0.38, green: 0.72, blue: 1.00)),
        .init(id: 1, name: "ELECTRIC BLUE", color: Color(red: 0.10, green: 0.48, blue: 1.00)),
        .init(id: 2, name: "NEON CYAN", color: Color(red: 0.08, green: 0.82, blue: 0.96)),
        .init(id: 3, name: "SKY BLUE", color: Color(red: 0.30, green: 0.66, blue: 0.98)),
        .init(id: 4, name: "ROYAL BLUE", color: Color(red: 0.14, green: 0.36, blue: 1.00)),
        .init(id: 5, name: "DEEP BLUE", color: Color(red: 0.08, green: 0.20, blue: 0.78)),
        .init(id: 6, name: "LASER BLUE", color: Color(red: 0.22, green: 0.58, blue: 1.00)),
        .init(id: 7, name: "AQUA GLOW", color: Color(red: 0.06, green: 0.78, blue: 0.90)),
        .init(id: 8, name: "BLUE WHITE", color: Color(red: 0.78, green: 0.92, blue: 1.00)),
        .init(id: 9, name: "FROST", color: Color(red: 0.62, green: 0.84, blue: 0.98)),
        .init(id: 10, name: "MIDNIGHT", color: Color(red: 0.05, green: 0.10, blue: 0.25)),
        .init(id: 11, name: "NAVY", color: Color(red: 0.06, green: 0.14, blue: 0.36)),
        .init(id: 12, name: "COBALT", color: Color(red: 0.10, green: 0.28, blue: 0.70)),
        .init(id: 13, name: "SAPPHIRE", color: Color(red: 0.12, green: 0.42, blue: 0.86)),
        .init(id: 14, name: "GLACIER", color: Color(red: 0.42, green: 0.76, blue: 1.00)),
        .init(id: 15, name: "OCEAN", color: Color(red: 0.04, green: 0.50, blue: 0.78)),
        .init(id: 16, name: "SILVER BLUE", color: Color(red: 0.72, green: 0.82, blue: 0.94)),
        .init(id: 17, name: "PEARL BLUE", color: Color(red: 0.90, green: 0.96, blue: 1.00)),
        .init(id: 18, name: "STEEL BLUE", color: Color(red: 0.32, green: 0.46, blue: 0.62)),
        .init(id: 19, name: "SIGNATURE BLUE", color: Color(red: 0.20, green: 0.62, blue: 1.00))
    ]

    static var accent: Color {
        let stored = UserDefaults.standard.integer(forKey: accentStorageKey)
        let index = min(max(stored, 0), palette.count - 1)
        return palette[index].color
    }

    static var selectedAccent: AppAccentOption {
        let stored = UserDefaults.standard.integer(forKey: accentStorageKey)
        let index = min(max(stored, 0), palette.count - 1)
        return palette[index]
    }

    static let pageBackground = Color(red: 0.006, green: 0.012, blue: 0.028)
    static let consoleBackground = Color(red: 0.012, green: 0.024, blue: 0.055)
    static let referenceCard = Color.white.opacity(0.07)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "TryStoreTheme")
                ?? UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

