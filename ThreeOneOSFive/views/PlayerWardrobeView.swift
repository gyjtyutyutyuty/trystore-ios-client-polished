import SwiftUI

/// Wardrobe tab: one Free Fire ID in, that player's equipped clothes
/// downloaded and worn by the bundled character.
///
/// Everything happens inside the app. The profile check uses the JSON preview
/// API; the equipped list and every garment mesh are read by hidden web views
/// that are never shown, so no browser opens and no external page appears.
/// Tapping an item only opens a native card.
struct PlayerWardrobeView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("hero_character_model") private var heroModelRaw = HeroCharacterModel.rouk.rawValue

    @State private var uidInput = ""
    @State private var profile: PlayerIntelProfile?
    @State private var items: [PlayerOutfitItem] = []
    @State private var garments: [PlayerGarment] = []
    @State private var phase: WardrobePhase = .idle
    @State private var errorKey: String?
    @State private var selectedItem: PlayerOutfitItem?
    @State private var isVisible = false
    @State private var hasMesh = true
    @State private var modelsDone = 0
    @State private var modelsTotal = 0
    @State private var modelsFailed = 0
    /// Downloaded garments the stage could not parse or place. Kept apart from
    /// `modelsFailed`, which counts downloads that never arrived.
    @State private var unreadableGarments = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var isFFHubPresented = false

    @FocusState private var fieldFocused: Bool

    /// What the tab is doing, so the spinner always has a sentence beside it.
    private enum WardrobePhase: Equatable {
        case idle
        case profile
        case outfit
        case meshes(done: Int, total: Int)
        case ready
        case failed
    }

    private var model: HeroCharacterModel {
        HeroCharacterModel(rawValue: heroModelRaw) ?? .rouk
    }

    private var modelBinding: Binding<HeroCharacterModel> {
        Binding(
            get: { model },
            set: { heroModelRaw = $0.rawValue }
        )
    }

    /// Same rule the stage uses: a 3D marker, a page to mint the ticket from,
    /// and a body slot to hang the mesh on.
    private var wearableItems: [PlayerOutfitItem] {
        items.filter { $0.has3D && $0.pageURL != nil && $0.slot.garmentFit != nil }
    }

    private var anchoredItems: [PlayerOutfitItem] {
        items.filter { $0.slot.stageAnchor != nil }
    }

    private var trimmedInput: String {
        uidInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Both download misses and unreadable files leave a slot empty, so the
    /// stage status reports them together.
    private var failedModelCount: Int {
        modelsFailed + unreadableGarments
    }

    private var isBusy: Bool {
        switch phase {
        case .profile, .outfit, .meshes: return true
        case .idle, .ready, .failed: return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBar.appCinematicReveal(delay: 0.02)
                        loadPanel.appCinematicReveal(delay: 0.08)

                        if let profile {
                            playerPanel(profile).appCinematicReveal(delay: 0.12)
                        }

                        stagePanel.appCinematicReveal(delay: 0.16)

                        if let selectedItem {
                            detailPanel(selectedItem).appCinematicReveal(delay: 0.02)
                        }

                        if !items.isEmpty {
                            itemsPanel.appCinematicReveal(delay: 0.20)
                        }

                        footer.appCinematicReveal(delay: 0.26)
                    }
                    .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 900)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.tabBarClearance)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(language.text("common.done")) { fieldFocused = false }
                }
            }
            .tint(AppTheme.accent)
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            loadTask?.cancel()
            loadTask = nil
        }
        .sheet(isPresented: $isFFHubPresented) {
            FFHubControlView()
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: AppSpacing.m) {
            FreeFireLogo(size: horizontalSizeClass == .compact ? 38 : 46)

            VStack(alignment: .leading, spacing: 4) {
                if let profile {
                    headerStats(profile)
                } else {
                    Text(language.text("wardrobe.title"))
                        .font(.system(
                            size: horizontalSizeClass == .compact ? 17 : 20,
                            weight: .black,
                            design: .rounded
                        ))
                        .tracking(horizontalSizeClass == .compact ? 1.0 : 1.5)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text(language.text("wardrobe.kicker"))
                        .font(AppType.label())
                        .tracking(0.7)
                        .foregroundStyle(AppTheme.accent.opacity(0.85))
                }
            }

            Spacer(minLength: AppSpacing.xs)

            Button {
                AppHaptics.tap()
                isFFHubPresented = true
            } label: {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppPalette.canvas, in: Circle())
                    .overlay(
                        Circle().strokeBorder(AppTheme.accent.opacity(0.28), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("ffhub.control"))
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.panel)
    }

    /// The loaded player's numbers replace the tab name in the header: both
    /// player tools share one tab now, so the title was repeating itself.
    private func headerStats(_ profile: PlayerIntelProfile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            headerStat("\(profile.level)", language.text("intel.level"))
            headerStat(profile.likes.formatted(), language.text("intel.likes"))
            headerStat(rankValue(profile), language.text("intel.rank"))
        }
        .accessibilityElement(children: .combine)
    }

    private func headerStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(AppPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(AppPalette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - ID entry

    private var loadPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "number")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.textTertiary)
                    .accessibilityHidden(true)

                TextField(language.text("wardrobe.prompt"), text: $uidInput)
                    .font(AppType.body())
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit { start() }
                    .accessibilityLabel(language.text("wardrobe.prompt"))

                if !uidInput.isEmpty {
                    Button {
                        uidInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text("common.clear"))
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .frame(minHeight: 46)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )

            AppActionButton(
                title: language.text("wardrobe.load"),
                icon: "tshirt.fill",
                isEnabled: !trimmedInput.isEmpty && !isBusy,
                action: start
            )

            Text(language.text("wardrobe.hint"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorKey {
                Text(language.text(errorKey))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    // MARK: - Player

    private func playerPanel(_ profile: PlayerIntelProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.nickname)
                        .font(AppType.display())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.s) {
                        if !profile.region.isEmpty {
                            AppStatChip(icon: "globe", text: profile.region)
                        }
                        AppStatChip(icon: "number", text: profile.uid)
                    }
                }

                Spacer(minLength: 0)

                if let url = profile.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(AppTheme.accent.opacity(0.35), lineWidth: 1))
                    .accessibilityHidden(true)
                } else {
                    avatarPlaceholder
                        .frame(width: 64, height: 64)
                }
            }

            HStack(spacing: AppSpacing.s) {
                AppMetricTile(
                    icon: "arrow.up.forward",
                    label: language.text("intel.level"),
                    value: "\(profile.level)"
                )
                AppMetricTile(
                    icon: "heart.fill",
                    label: language.text("intel.likes"),
                    value: profile.likes.formatted()
                )
                AppMetricTile(
                    icon: "trophy.fill",
                    label: language.text("intel.rank"),
                    value: rankValue(profile)
                )
            }
        }
        .padding(AppSpacing.l)
        .background { playerBannerArt }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(AppPalette.canvas)
            Image(systemName: "person.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(AppPalette.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private func rankValue(_ profile: PlayerIntelProfile) -> String {
        guard let rank = profile.rank, !rank.isEmpty else { return "—" }
        guard let points = profile.rankPoints else { return rank }
        return "\(rank) · \(points)"
    }

    /// Turns the real game artwork into a quiet banner behind the player
    /// numbers, dark enough that the stats stay the focus.
    private var playerBannerArt: some View {
        ZStack {
            Image("FreeFireMax")
                .resizable()
                .scaledToFill()
                .opacity(0.22)

            LinearGradient(
                colors: [
                    AppPalette.raised.opacity(0.30),
                    AppPalette.raised.opacity(0.90),
                    AppPalette.raised
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    // MARK: - Stage

    private var stageHeader: some View {
        AppSectionHeader(
            icon: "cube.transparent",
            title: language.text("intel.character")
        )
    }

    private var stageHeaderRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppSpacing.m) {
                stageHeader
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: AppSpacing.s)
                HeroCharacterSwitcher(selection: modelBinding)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                stageHeader
                HStack {
                    Spacer(minLength: 0)
                    HeroCharacterSwitcher(selection: modelBinding)
                }
            }
        }
    }

    private var stagePanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            stageHeaderRow

            ZStack {
                if hasMesh {
                    CharacterStageView(
                        model: model,
                        reduceMotion: reduceMotion,
                        isActive: isVisible,
                        garments: garments,
                        onGarmentFailures: { unreadableGarments = $0 }
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

            phaseStatus

            Text(language.text("intel.outfit_note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    @ViewBuilder
    private var phaseStatus: some View {
        switch phase {
        case .idle:
            Text(language.text("wardrobe.idle_message"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .profile:
            statusRow(language.text("wardrobe.stage_profile"))
        case .outfit:
            statusRow(language.text("wardrobe.stage_outfit"))
        case .meshes(let done, let total):
            statusRow(language.text("wardrobe.stage_meshes", done, total))
        case .ready:
            HStack(spacing: AppSpacing.s) {
                Image(systemName: failedModelCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(failedModelCount > 0 ? AppPalette.amber : AppTheme.accent)
                Text(failedModelCount > 0
                    ? language.text("intel.models_partial", failedModelCount, modelsTotal)
                    : language.text("wardrobe.stage_ready"))
                Spacer(minLength: 0)
            }
            .font(AppType.meta())
            .foregroundStyle(AppPalette.textTertiary)
            .accessibilityElement(children: .combine)
        case .failed:
            EmptyView()
        }
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            ProgressView().tint(AppTheme.accent)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(AppType.meta())
        .foregroundStyle(AppPalette.textTertiary)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Badges

    private var badgeLayer: some View {
        GeometryReader { geometry in
            ForEach(anchoredItems) { item in
                if let anchor = item.slot.stageAnchor {
                    Button {
                        AppHaptics.select()
                        selectedItem = item
                    } label: {
                        badge(for: item)
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .position(
                        x: geometry.size.width * anchor.x,
                        y: geometry.size.height * anchor.y
                    )
                    .accessibilityLabel("\(language.text(item.slot.localizationKey)): \(item.name)")
                    .accessibilityHint(language.text("wardrobe.tap_item"))
                }
            }
        }
    }

    private func badge(for item: PlayerOutfitItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(AppPalette.raised)
                Circle().strokeBorder(AppTheme.accent.opacity(0.55), lineWidth: 1)

                if let iconURL = item.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(4)
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

            if garments.contains(where: { $0.id == item.id }) {
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

    // MARK: - Native item card

    private func detailPanel(_ item: PlayerOutfitItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.m) {
                itemIcon(item)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(AppType.section())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(2)

                    Text(detailLine(item))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button {
                    AppHaptics.tap()
                    selectedItem = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppPalette.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .background(AppPalette.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("common.close"))
            }

            HStack(spacing: AppSpacing.s) {
                Image(systemName: statusIcon(item))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusTint(item))
                Text(statusLine(item))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func itemIcon(_ item: PlayerOutfitItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.canvas)

            if let url = item.iconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(4)
                    default:
                        slotGlyph(item.slot)
                    }
                }
            } else {
                slotGlyph(item.slot)
            }
        }
        .accessibilityHidden(true)
    }

    private func detailLine(_ item: PlayerOutfitItem) -> String {
        let parts = [language.text(item.slot.localizationKey), item.rarity]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func statusLine(_ item: PlayerOutfitItem) -> String {
        if garments.contains(where: { $0.id == item.id }) {
            return language.text("wardrobe.worn")
        }
        if item.has3D {
            return language.text("wardrobe.pending")
        }
        return language.text("wardrobe.no_model")
    }

    private func statusIcon(_ item: PlayerOutfitItem) -> String {
        if garments.contains(where: { $0.id == item.id }) { return "checkmark.circle.fill" }
        return item.has3D ? "arrow.down.circle" : "xmark.circle"
    }

    private func statusTint(_ item: PlayerOutfitItem) -> Color {
        if garments.contains(where: { $0.id == item.id }) { return AppTheme.accent }
        return item.has3D ? AppPalette.textSecondary : AppPalette.amber
    }

    // MARK: - Items

    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(
                icon: "tshirt.fill",
                title: language.text("intel.outfit"),
                subtitle: language.text("intel.outfit_count", items.count)
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)],
                spacing: AppSpacing.s
            ) {
                ForEach(items) { item in
                    Button {
                        AppHaptics.select()
                        selectedItem = item
                    } label: {
                        itemCard(item)
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .accessibilityLabel("\(item.name), \(detailLine(item))")
                    .accessibilityHint(language.text("wardrobe.tap_item"))
                }
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func itemCard(_ item: PlayerOutfitItem) -> some View {
        let worn = garments.contains(where: { $0.id == item.id })

        return HStack(spacing: AppSpacing.s) {
            itemIcon(item)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(AppType.body().weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                Text(detailLine(item))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: worn ? "cube.fill" : (item.has3D ? "cube" : "minus.circle"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(worn ? AppTheme.accent : AppPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(worn ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: AppSpacing.s) {
            if let url = profile?.profileURL {
                Link(destination: url) {
                    Label(language.text("intel.open_profile"), systemImage: "arrow.up.right.square")
                        .font(AppType.label())
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Text(language.text("wardrobe.note"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func start() {
        guard !isBusy else { return }

        let uid = trimmedInput
        guard (8...20).contains(uid.count), uid.allSatisfy({ $0.isNumber }) else {
            errorKey = "intel.error_invalid"
            return
        }

        loadTask?.cancel()
        fieldFocused = false
        loadTask = Task { await load(uid: uid) }
    }

    @MainActor
    private func load(uid: String) async {
        errorKey = nil
        profile = nil
        items = []
        garments = []
        selectedItem = nil
        modelsDone = 0
        modelsTotal = 0
        modelsFailed = 0
        unreadableGarments = 0
        phase = .profile

        do {
            let profile = try await PlayerIntelService.shared.profile(
                uid: uid,
                language: language.rawValue
            )
            guard !Task.isCancelled else { return }
            self.profile = profile

            phase = .outfit
            do {
                let outfit = try await PlayerOutfitScraper.shared.outfit(uid: uid)
                guard !Task.isCancelled else { return }
                items = outfit
            } catch {
                guard !Task.isCancelled else { return }
                items = []
                errorKey = (error as? PlayerIntelError)?.messageKey ?? "intel.error_outfit"
            }

            await downloadMeshes()
        } catch {
            guard !Task.isCancelled else { return }
            errorKey = (error as? PlayerIntelError)?.messageKey ?? "intel.error_network"
            phase = .failed
        }
    }

    /// The meshes are the slow part, so every item downloads in parallel behind
    /// the downloader's own gate and each result lands on the character as it
    /// arrives.
    @MainActor
    private func downloadMeshes() async {
        let targets = wearableItems
        modelsTotal = targets.count
        modelsDone = 0
        modelsFailed = 0
        unreadableGarments = 0

        guard !targets.isEmpty else {
            phase = .ready
            return
        }

        phase = .meshes(done: 0, total: targets.count)

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
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let result {
                    garments.append(result)
                } else {
                    modelsFailed += 1
                }
                modelsDone += 1
                phase = .meshes(done: modelsDone, total: targets.count)
            }
        }

        phase = .ready
    }
}

// MARK: - Player hub

/// Intel and wardrobe were two tabs with the same lookup flow. One tab with a
/// segmented switch keeps both tools reachable and gives the tab bar a slot
/// back, without rewriting either screen.
struct PlayerHubView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("player_hub_mode") private var modeRaw = PlayerHubMode.wardrobe.rawValue

    private enum PlayerHubMode: String {
        case wardrobe
        case intel
    }

    private var mode: PlayerHubMode {
        PlayerHubMode(rawValue: modeRaw) ?? .wardrobe
    }

    var body: some View {
        ZStack {
            // One backdrop for the whole tab, including the switcher strip.
            // The wardrobe and intel children used to own it separately, which
            // left the top bar over the window's black background.
            AppPremiumBackdrop()

            VStack(spacing: 0) {
                switcher
                Group {
                    switch mode {
                    case .wardrobe:
                        PlayerWardrobeView()
                    case .intel:
                        PlayerIntelView()
                    }
                }
            }
        }
    }

    private var switcher: some View {
        HStack(spacing: AppSpacing.xs) {
            segment(.wardrobe, icon: "hanger", key: "tab.wardrobe")
            segment(.intel, icon: "chart.bar.fill", key: "tab.intel")
        }
        .padding(AppSpacing.xs)
        .background(AppPalette.surface, in: Capsule())
        .overlay(
            Capsule().strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.screenInset)
        .padding(.top, AppSpacing.s)
        .padding(.bottom, AppSpacing.xs)
    }

    private func segment(_ target: PlayerHubMode, icon: String, key: String) -> some View {
        Button {
            guard mode != target else { return }
            AppHaptics.select()
            modeRaw = target.rawValue
        } label: {
            Label(language.text(key), systemImage: icon)
                .font(AppType.label().weight(.semibold))
                .foregroundStyle(mode == target ? AppPalette.canvas : AppPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(mode == target ? AppTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == target ? [.isSelected] : [])
    }
}
