import SwiftUI
import UIKit

struct PatchPayloadImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let label: String
}

/// Two payloads from the same package, split by a divider the finger owns.
/// Comparing NECK against HEAD before applying is the whole product in one
/// gesture, and it only appears when a package really carries two images.
struct PatchPayloadPreview: View {
    let leading: PatchPayloadImage
    let trailing: PatchPayloadImage

    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var split: CGFloat = 0.5

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.canvas.ignoresSafeArea()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        pane(leading.image)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()

                        pane(trailing.image)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: max(0, proxy.size.width * split))
                            }

                        divider(height: proxy.size.height)
                            .offset(x: proxy.size.width * split - 1)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                split = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                            }
                    )
                }
                .padding(.horizontal, AppSpacing.l)

                VStack {
                    HStack {
                        labelChip(leading.label, tint: AppPalette.textSecondary)
                        Spacer(minLength: AppSpacing.s)
                        labelChip(trailing.label, tint: AppPalette.brand)
                    }
                    .padding(.horizontal, AppSpacing.l)
                    Spacer(minLength: 0)
                    Text(language.text("patch.preview.hint"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .padding(.bottom, AppSpacing.m)
                }
            }
            .navigationTitle(language.text("patch.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.close")) { dismiss() }
                }
            }
        }
    }

    private func pane(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func divider(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(AppPalette.textPrimary.opacity(0.85))
                .frame(width: 1.5, height: height * 0.72)
            Circle()
                .fill(AppPalette.surface)
                .frame(width: 30, height: 30)
                .overlay {
                    Circle().strokeBorder(AppPalette.brand.opacity(0.8), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppPalette.brand)
                }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 8)
        .accessibilityHidden(true)
    }

    private func labelChip(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppPalette.raised.opacity(0.92), in: Capsule())
            .overlay {
                Capsule().strokeBorder(AppPalette.hairline.opacity(0.6), lineWidth: 1)
            }
    }
}

extension PatchRule {
    /// Cheap magic-byte check so a package with a dozen binary payloads never
    /// pays for a full decode just to decide whether the preview exists.
    var payloadLooksLikeImage: Bool {
        let bytes = [UInt8](replacementData.prefix(4))
        guard bytes.count == 4 else { return false }
        if bytes[0] == 0x89 && bytes[1] == 0x50 { return true }          // PNG
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return true }          // JPEG
        if bytes[0] == 0x47 && bytes[1] == 0x49 { return true }          // GIF
        return false
    }
}
