import SwiftUI

/// The selected player's equipped set laid over the bundled 3D character.
///
/// Items with a catalogue mesh are downloaded and hung on the body by slot.
/// Items without one keep their badge on the matching body region, and every
/// item still opens its own page.
struct PlayerOutfitStage: View {
    let items: [PlayerOutfitItem]
    @Binding var model: HeroCharacterModel
    let isActive: Bool
    let onOpenItem: (PlayerOutfitItem) -> Void

    @Environment(\.appLanguage) private var language
    @Environment(\.appReduceMotion) private var reduceMotion

    @State private var hasMesh = true
    @State private var garments: [PlayerGarment] = []
    @State private var modelTotal = 0
    @State private var modelDone = 0
    @State private var modelFailed = 0
    @State private var modelToken = UUID()

    private var anchoredItems: [PlayerOutfitItem] {
        items.filter { $0.slot.stageAnchor != nil }
    }

    /// Only items the catalogue can actually hand over: a 3D marker, a page to
    /// mint the ticket from, and a body slot to hang the mesh on.
    private var wearableItems: [PlayerOutfitItem] {
        items.filter { $0.has3D && $0.pageURL != nil && $0.slot.garmentFit != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .center, spacing: AppSpacing.m) {
                AppSectionHeader(
                    icon: "cube.transparent",
                    title: language.text("intel.character")
                )
                Spacer(minLength: AppSpacing.s)
                HeroCharacterSwitcher(selection: $model)
            }

            ZStack {
                if hasMesh {
                    CharacterStageView(
                        model: model,
                        reduceMotion: reduceMotion,
                        isActive: isActive,
                        garments: garments
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    badgeLayer
                } else {
                    AppEmptyState(
                        icon: "cube.transparent",
                        title: language.text("intel.character"),
                        message: language.text("intel.character_missing")
                    )
                    .padding(AppSpacing.l)
                }
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
            .task(id: model) {
                hasMesh = CharacterVault.modelURL(model) != nil
            }

            modelStatus

            Text(language.text("intel.outfit_note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
        .task(id: items) {
            await loadModels()
        }
    }

    // MARK: - Model progress

    @ViewBuilder
    private var modelStatus: some View {
        if modelTotal > 0 {
            HStack(spacing: AppSpacing.s) {
                if modelDone < modelTotal {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text(language.text("intel.models_progress", modelDone, modelTotal))
                } else if modelFailed > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppPalette.amber)
                    Text(language.text("intel.models_partial", modelFailed, modelTotal))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(language.text("intel.models_ready"))
                }

                Spacer(minLength: 0)
            }
            .font(AppType.meta())
            .foregroundStyle(AppPalette.textTertiary)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Download

    @MainActor
    private func loadModels() async {
        let token = UUID()
        modelToken = token

        let targets = wearableItems
        modelTotal = targets.count
        modelDone = 0
        modelFailed = 0
        garments = []

        guard !targets.isEmpty else { return }

        await withTaskGroup(of: PlayerGarment?.self) { group in
            for item in targets {
                group.addTask {
                    guard let url = try? await GarmentDownloader.shared.download(item: item) else {
                        return nil
                    }
                    return PlayerGarment(id: item.id, slot: item.slot, url: url)
                }
            }

            for await result in group {
                guard !Task.isCancelled, modelToken == token else {
                    group.cancelAll()
                    return
                }

                if let result {
                    garments.append(result)
                } else {
                    modelFailed += 1
                }
                modelDone += 1
            }
        }
    }

    // MARK: - Badges

    private var badgeLayer: some View {
        GeometryReader { geometry in
            ForEach(anchoredItems) { item in
                if let anchor = item.slot.stageAnchor {
                    Button {
                        AppHaptics.select()
                        onOpenItem(item)
                    } label: {
                        badge(for: item)
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .position(
                        x: geometry.size.width * anchor.x,
                        y: geometry.size.height * anchor.y
                    )
                    .accessibilityLabel(
                        "\(language.text(item.slot.localizationKey)): \(item.name)"
                    )
                    .accessibilityHint(language.text("intel.open_3d"))
                    .disabled(item.pageURL == nil)
                }
            }
        }
    }

    private func badge(for item: PlayerOutfitItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(AppPalette.raised)
                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.55), lineWidth: 1)

                if let iconURL = item.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        default:
                            slotGlyph(item.slot)
                        }
                    }
                } else {
                    slotGlyph(item.slot)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            if item.has3D {
                Image(systemName: "cube.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppPalette.canvas)
                    .padding(3)
                    .background(AppTheme.accent, in: Circle())
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private func slotGlyph(_ slot: PlayerOutfitSlot) -> some View {
        Image(systemName: Self.symbol(for: slot))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppPalette.textSecondary)
            .accessibilityHidden(true)
    }

    private static func symbol(for slot: PlayerOutfitSlot) -> String {
        switch slot {
        case .hair: return "scissors"
        case .face: return "paintbrush.fill"
        case .mask: return "theatermasks.fill"
        case .top: return "tshirt.fill"
        case .pants: return "figure.stand"
        case .shoes: return "figure.walk"
        case .pin: return "pin.fill"
        case .title: return "textformat"
        case .other: return "sparkles"
        }
    }
}
