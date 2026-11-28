import SwiftUI

/// Player lookup for Free Fire IDs. One ID is kept at a time: it loads the
/// public profile, every published stat block and the equipped items, and it
/// reopens unchanged on the next launch. Removing it frees the slot for
/// another.
struct PlayerIntelView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var roster: [PlayerIntelEntry] = PlayerRosterStore.load()
    @State private var selectedUID: String?
    /// The last ID that was entered, so the tab opens on the same player next
    /// launch instead of the top of the roster.
    @AppStorage("intel_last_uid") private var lastUID = ""
    @AppStorage("intel_query_draft") private var query = ""
    @State private var addErrorKey: String?
    @State private var activeItem: PlayerOutfitItem?
    @State private var tasks: [String: Task<Void, Never>] = [:]
    @FocusState private var searchFocused: Bool

    private var selectedEntry: PlayerIntelEntry? {
        if let selectedUID,
           let match = roster.first(where: { $0.uid == selectedUID }) {
            return match
        }
        return roster.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Inside the stack, not behind it: a NavigationStack paints its
                // own background, so an outside backdrop is never visible.
                AppPremiumBackdrop()
                HUDConsoleBackdrop(intensity: 0.9)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBar.appCinematicReveal(delay: 0.02)
                        addPanel.appCinematicReveal(delay: 0.08)

                        content.appCinematicReveal(delay: 0.14)

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
                    Button(language.text("common.done")) { searchFocused = false }
                }
            }
            .tint(AppTheme.accent)
        }
        .onAppear {
            if roster.isEmpty,
               (8...20).contains(lastUID.count),
               lastUID.allSatisfy({ $0.isNumber }) {
                // The roster store only appeared after the wardrobe merge, so a
                // remembered ID from an older install is reloaded once here.
                roster = [
                    PlayerIntelEntry(
                        uid: lastUID,
                        profile: nil,
                        items: [],
                        stats: nil,
                        outfitFailed: false,
                        errorKey: nil,
                        isLoading: true
                    )
                ]
                selectedUID = lastUID
                startLoad(lastUID)
                return
            }

            if selectedUID == nil || !roster.contains(where: { $0.uid == selectedUID }) {
                let remembered = roster.first(where: { $0.uid == lastUID })?.uid
                selectedUID = remembered ?? roster.first?.uid
            }
        }
        .onChange(of: selectedUID) { uid in
            guard let uid else { return }
            lastUID = uid
        }
        .onDisappear {
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
        }
        .onChange(of: roster) { updated in
            PlayerRosterStore.save(updated)
        }
        .sheet(item: $activeItem) { item in
            PlayerItemDetailSheet(item: item)
        }
    }

    // MARK: - Header

    private var topBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppPalette.brand)
                    .frame(width: 5, height: 5)
                    .shadow(color: AppPalette.brand.opacity(0.9), radius: 5)
                Text(language.text("intel.kicker"))
                    .font(AppType.hudKicker())
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.xs)
                Text(language.text("tab.intel"))
                    .font(AppType.hudKicker().weight(.black))
                    .foregroundStyle(AppPalette.brand)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(AppPalette.brand.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(AppPalette.brand.opacity(0.30), lineWidth: 0.8))
            }

            HStack(spacing: AppSpacing.m) {
                FreeFireLogo(size: horizontalSizeClass == .compact ? 38 : 46)

                VStack(alignment: .leading, spacing: 4) {
                    if let profile = selectedEntry?.profile {
                        headerStats(profile)
                    } else {
                        Text(language.text("intel.title"))
                            .font(.system(
                                size: horizontalSizeClass == .compact ? 17 : 20,
                                weight: .black,
                                design: .rounded
                            ))
                            .tracking(horizontalSizeClass == .compact ? 1.0 : 1.5)
                            .foregroundStyle(AppPalette.textPrimary)
                    }
                }

                Spacer(minLength: AppSpacing.xs)
            }
        }
        .padding(AppSpacing.m)
        .appHUDPanel(cut: 20)
    }

    /// Stats replace the screen name in the header, matching the wardrobe half
    /// of the shared player tab.
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

    // MARK: - Add players

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "number")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.textTertiary)
                        .accessibilityHidden(true)

                    TextField(language.text("intel.search_prompt"), text: $query)
                        .font(AppType.body())
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .submitLabel(.done)
                        .onSubmit(addPlayers)
                        .accessibilityLabel(language.text("intel.search_prompt"))

                    if !query.isEmpty {
                        Button {
                            query = ""
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
                .frame(minHeight: 48)
                .background(
                    AppHUD.deep,
                    in: AppChamferShape(cut: 10)
                )
                .overlay(
                    AppChamferShape(cut: 10)
                        .stroke(AppPalette.brand.opacity(0.22), lineWidth: 0.8)
                )

                Button(action: addPlayers) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.canvas)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: AppChamferShape(cut: 10)
                        )
                }
                .buttonStyle(AppPressButtonStyle())
                .disabled(trimmedQuery.isEmpty)
                .opacity(trimmedQuery.isEmpty ? 0.4 : 1)
                .accessibilityLabel(language.text("intel.add_player"))
            }

            if roster.isEmpty {
                Text(language.text("intel.add_hint"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let addErrorKey {
                Label(language.text(addErrorKey), systemImage: "exclamationmark.triangle.fill")
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.l)
        .appHUDPanel(cut: 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let entry = selectedEntry {
            if let profile = entry.profile {
                VStack(spacing: AppSpacing.l) {
                    HUDSectionHeader(
                        index: "01",
                        icon: "person.crop.rectangle.fill",
                        title: language.text("intel.title"),
                        subtitle: language.text("intel.kicker")
                    )
                    profilePanel(profile)
                    statsPanel(entry)
                    outfitPanel(entry)
                }
            } else if entry.isLoading {
                loadingPanel
            } else if let errorKey = entry.errorKey {
                errorPanel(errorKey, uid: entry.uid)
            }
        } else {
            idlePanel
        }
    }

    // MARK: - Profile

    private func profilePanel(_ profile: PlayerIntelProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                avatar(profile, size: 76)
                    .padding(3)
                    .background(AppPalette.canvas.opacity(0.72), in: Circle())
                    .overlay(
                        Circle().strokeBorder(AppTheme.accent.opacity(0.55), lineWidth: 1.5)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text(profile.nickname)
                        .font(AppType.display())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: AppPalette.canvas.opacity(0.7), radius: 8, y: 2)

                    HStack(spacing: AppSpacing.s) {
                        if !profile.region.isEmpty {
                            AppStatChip(icon: "globe", text: profile.region)
                        }
                        AppStatChip(icon: "number", text: profile.uid)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: AppSpacing.xs) {
                    cardButton(icon: "arrow.clockwise", label: language.text("intel.retry")) {
                        startLoad(profile.uid)
                    }
                    cardButton(icon: "xmark", label: language.text("intel.remove_player")) {
                        AppHaptics.tap()
                        remove(profile.uid)
                    }
                }
            }

            Spacer(minLength: AppSpacing.xl)

            HStack(spacing: AppSpacing.s) {
                AppMetricTile(
                    icon: "arrow.up.forward",
                    label: language.text("intel.level"),
                    value: "\(profile.level)",
                    minHeight: 72
                )
                AppMetricTile(
                    icon: "heart.fill",
                    label: language.text("intel.likes"),
                    value: profile.likes.formatted(),
                    minHeight: 72
                )
                AppMetricTile(
                    icon: "trophy.fill",
                    label: language.text("intel.rank"),
                    value: rankValue(profile),
                    minHeight: 72
                )
            }
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
        .background { profileBannerArt }
        .clipShape(AppChamferShape(cut: 22))
        .overlay(
            AppChamferShape(cut: 22)
                .stroke(AppPalette.brand.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: AppPalette.brand.opacity(0.18), radius: 18, y: 8)
    }

    /// The real Free Fire MAX key art, shown rather than hinted at: a directional
    /// scrim keeps the nickname readable on the left while the art stays visible
    /// on the right, and a bottom fade seats the stat tiles.
    private var profileBannerArt: some View {
        ZStack {
            Image("FFMaxBanner")
                .resizable()
                .scaledToFill()

            LinearGradient(
                stops: [
                    .init(color: AppPalette.canvas.opacity(0.92), location: 0.0),
                    .init(color: AppPalette.canvas.opacity(0.66), location: 0.46),
                    .init(color: AppPalette.canvas.opacity(0.28), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    AppPalette.canvas.opacity(0.10),
                    AppPalette.canvas.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private func cardButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.textSecondary)
                .frame(width: 44, height: 44)
                .background(AppPalette.canvas, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Stats

    @ViewBuilder
    private func statsPanel(_ entry: PlayerIntelEntry) -> some View {
        if let stats = entry.stats, !stats.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HUDSectionHeader(
                    index: "02",
                    icon: "chart.bar.xaxis",
                    title: language.text("intel.stats.title"),
                    subtitle: language.text("intel.stats.subtitle")
                )

                HStack(spacing: AppSpacing.s) {
                    AppMetricTile(
                        icon: "arrow.up.forward",
                        label: language.text("intel.stats.level"),
                        value: stats.level.isEmpty ? "—" : stats.level,
                        minHeight: 72
                    )
                    AppMetricTile(
                        icon: "sparkles",
                        label: language.text("intel.stats.exp"),
                        value: stats.experience.isEmpty ? "—" : stats.experience,
                        minHeight: 72
                    )
                    AppMetricTile(
                        icon: "heart.fill",
                        label: language.text("intel.stats.likes"),
                        value: stats.likes.isEmpty ? "—" : stats.likes,
                        minHeight: 72
                    )
                }

                if let line = stats.battleRoyale {
                    rankCard(
                        title: language.text("intel.stats.battle_royale"),
                        line: line,
                        pointsKey: "intel.stats.points",
                        peakKey: "intel.stats.peak_points"
                    )
                }

                if let line = stats.clashSquad {
                    rankCard(
                        title: language.text("intel.stats.clash_squad"),
                        line: line,
                        pointsKey: "intel.stats.stars",
                        peakKey: "intel.stats.best_record"
                    )
                }

                if let totals = stats.totals, !totals.isEmpty {
                    totalGrid(totals)
                }

                if let modes = stats.modes, !modes.isEmpty {
                    ForEach(modes) { mode in
                        modeCard(mode)
                    }
                }

                if let role = stats.role, !role.isEmpty {
                    HStack(spacing: AppSpacing.s) {
                        AppIconBadge(systemName: "shield.lefthalf.filled", size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text("intel.stats.role"))
                                .font(AppType.label())
                                .foregroundStyle(AppPalette.textTertiary)
                            Text(stats.roleGroup.map { "\(role) · \($0)" } ?? role)
                                .font(AppType.body().weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(AppSpacing.m)
                    .background(
                        AppPalette.canvas,
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                }

                if let sections = stats.sections, !sections.isEmpty {
                    ForEach(sections) { section in
                        detailBlock(
                            title: section.title,
                            icon: "list.bullet.rectangle",
                            lines: section.rows
                        )
                    }
                } else {
                    if !stats.account.isEmpty {
                        detailBlock(
                            title: language.text("intel.stats.account"),
                            icon: "person.text.rectangle",
                            lines: stats.account
                        )
                    }

                    if !stats.indicators.isEmpty {
                        detailBlock(
                            title: language.text("intel.stats.indicators"),
                            icon: "checkmark.shield",
                            lines: stats.indicators
                        )
                    }
                }
            }
            .padding(AppSpacing.l)
            .appHUDPanel(cut: 22)
        }
    }

    /// Every match total the page publishes, as a compact scoreboard strip.
    private func totalGrid(_ totals: [PlayerStatLine]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 102), spacing: AppSpacing.s)],
            spacing: AppSpacing.s
        ) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, total in
                VStack(alignment: .leading, spacing: 2) {
                    Text(total.value.isEmpty ? "—" : total.value)
                        .font(AppType.value())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(total.label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(AppPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.m)
                .background(
                    AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One mode block: win-rate headline, three highlights, then every published
    /// row in a two-column grid so the whole profile stays scannable.
    private func modeCard(_ mode: PlayerModeStats) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Text(mode.mode.uppercased())
                    .font(AppType.label().weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !mode.headline.isEmpty {
                    Text(mode.headline)
                        .font(AppType.label().weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                }
            }

            if !mode.highlights.isEmpty {
                HStack(spacing: AppSpacing.s) {
                    ForEach(Array(mode.highlights.enumerated()), id: \.offset) { _, highlight in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.value.isEmpty ? "—" : highlight.value)
                                .font(AppType.value())
                                .foregroundStyle(AppPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(highlight.label.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(AppPalette.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(AppSpacing.m)
                .background(
                    AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148), spacing: AppSpacing.m)],
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(Array(mode.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: AppSpacing.s) {
                        Text(row.label)
                            .font(AppType.meta())
                            .foregroundStyle(AppPalette.textTertiary)
                            .lineLimit(1)
                        Spacer(minLength: AppSpacing.xs)
                        Text(row.value.isEmpty ? "—" : row.value)
                            .font(AppType.meta().weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, AppSpacing.s)
                }
            }
        }
        .padding(AppSpacing.m)
        .background(
            AppPalette.raised,
            in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func rankCard(
        title: String,
        line: PlayerRankLine,
        pointsKey: String,
        peakKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.m) {
                rankEmblem(line)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(line.rank.isEmpty ? "—" : line.rank)
                        .font(AppType.value())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                statRow(key: pointsKey, value: line.points)
                statRow(key: "intel.stats.best_rank", value: line.bestRank)
                statRow(key: peakKey, value: line.bestValue)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The real in-game emblem the profile page serves for this rank.
    @ViewBuilder
    private func rankEmblem(_ line: PlayerRankLine) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.canvas)

            if let url = line.iconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(4)
                    default:
                        emblemPlaceholder
                    }
                }
            } else {
                emblemPlaceholder
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private var emblemPlaceholder: some View {
        Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
    }

    private func statRow(key: String, value: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            Text(language.text(key))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: AppSpacing.xs)
            Text(value.isEmpty ? "—" : value)
                .font(AppType.meta().weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func detailBlock(
        title: String,
        icon: String,
        lines: [PlayerStatLine]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if !title.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textSecondary)
                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { AppHairline() }

                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                        Text(line.label)
                            .font(AppType.meta())
                            .foregroundStyle(AppPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(line.value.isEmpty ? "—" : line.value)
                            .font(AppType.meta().weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, AppSpacing.s)
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func avatar(_ profile: PlayerIntelProfile, size: CGFloat) -> some View {
        let shape = Circle()

        if let url = profile.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .accessibilityHidden(true)
        } else {
            avatarPlaceholder
                .frame(width: size, height: size)
        }
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

    // MARK: - Outfit

    private func outfitPanel(_ entry: PlayerIntelEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HUDSectionHeader(
                index: "03",
                icon: "hanger",
                title: language.text("intel.outfit"),
                subtitle: entry.items.isEmpty
                    ? nil
                    : language.text("intel.outfit_count", entry.items.count)
            )

            if entry.items.isEmpty {
                AppEmptyState(
                    icon: "hanger",
                    title: language.text("intel.outfit_empty"),
                    message: entry.outfitFailed
                        ? language.text("intel.error_outfit")
                        : language.text("intel.outfit_empty_hint"),
                    tint: entry.outfitFailed ? AppPalette.amber : AppTheme.accent
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: AppSpacing.s)],
                    spacing: AppSpacing.s
                ) {
                    ForEach(entry.items) { item in
                        Button {
                            AppHaptics.select()
                            activeItem = item
                        } label: {
                            itemCard(item)
                        }
                        .buttonStyle(AppPressButtonStyle())
                        .accessibilityLabel("\(item.name), \(itemDetail(item))")
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .appHUDPanel(cut: 22)
    }

    private func itemCard(_ item: PlayerOutfitItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(AppPalette.raised)

                itemIcon(item)
                    .padding(AppSpacing.m)

                if item.has3D {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppPalette.canvas)
                        .padding(4)
                        .background(AppTheme.accent, in: Circle())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 84)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(AppType.body().weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                Text(itemDetail(item))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func itemIcon(_ item: PlayerOutfitItem) -> some View {
        if let url = item.iconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    itemGlyph
                }
            }
        } else {
            itemGlyph
        }
    }

    private var itemGlyph: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppPalette.textSecondary)
            .accessibilityHidden(true)
    }

    private func itemDetail(_ item: PlayerOutfitItem) -> String {
        let parts = [language.text(item.slot.localizationKey), item.rarity]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    // MARK: - States

    private var loadingPanel: some View {
        HStack(spacing: AppSpacing.m) {
            ProgressView()
                .tint(AppTheme.accent)
            Text(language.text("intel.loading"))
                .font(AppType.body())
                .foregroundStyle(AppPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.l)
        .appHUDPanel(cut: 18)
        .accessibilityElement(children: .combine)
    }

    private var idlePanel: some View {
        AppEmptyState(
            icon: "person.text.rectangle",
            title: language.text("intel.empty_title"),
            message: language.text("intel.empty_message")
        )
        .padding(AppSpacing.l)
        .appHUDPanel(cut: 18)
    }

    private func errorPanel(_ key: String, uid: String) -> some View {
        VStack(spacing: AppSpacing.m) {
            AppEmptyState(
                icon: "exclamationmark.triangle",
                title: language.text("intel.title"),
                message: language.text(key),
                tint: AppPalette.amber
            )
            AppActionButton(
                title: language.text("intel.retry"),
                icon: "arrow.clockwise",
                isProminent: false,
                isEnabled: true,
                action: { startLoad(uid) }
            )
        }
        .padding(AppSpacing.l)
        .appHUDPanel(cut: 18)
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.s) {
            if let updated = updatedText {
                Text(updated)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var updatedText: String? {
        guard let raw = selectedEntry?.profile?.updatedAt else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else { return nil }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        display.locale = language.locale
        return language.text("intel.updated", display.string(from: date))
    }

    private func addPlayers() {
        let uids = Self.parseUIDs(query)
        guard !uids.isEmpty else {
            addErrorKey = "intel.error_invalid"
            return
        }

        addErrorKey = nil
        lastUID = uids[0]
        query = ""
        searchFocused = false

        // One ID is kept at a time. Adding another replaces the stored one, so
        // the key never accumulates players.
        let uid = uids[0]
        roster = [
            PlayerIntelEntry(
                uid: uid,
                profile: nil,
                items: [],
                stats: nil,
                outfitFailed: false,
                errorKey: nil,
                isLoading: true
            )
        ]
        selectedUID = uid
        PlayerRosterStore.save(roster)
        startLoad(uid)
    }

    private func startLoad(_ uid: String) {
        tasks[uid]?.cancel()
        tasks[uid] = Task { await load(uid: uid) }
    }

    @MainActor
    private func load(uid: String) async {
        update(uid) { entry in
            entry.isLoading = true
            entry.errorKey = nil
        }

        do {
            let profile = try await PlayerIntelService.shared.profile(
                uid: uid,
                language: language.rawValue
            )
            guard !Task.isCancelled else { return }
            update(uid) { $0.profile = profile }

            do {
                let page = try await PlayerOutfitScraper.shared.page(uid: uid)
                guard !Task.isCancelled else { return }
                update(uid) { entry in
                    entry.items = page.items
                    entry.stats = page.stats
                    entry.outfitFailed = false
                    entry.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                update(uid) { entry in
                    entry.items = []
                    entry.outfitFailed = true
                    entry.isLoading = false
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            let key = (error as? PlayerIntelError)?.messageKey ?? "intel.error_network"
            update(uid) { entry in
                entry.errorKey = key
                entry.isLoading = false
            }
        }
    }

    private func update(_ uid: String, _ change: (inout PlayerIntelEntry) -> Void) {
        guard let index = roster.firstIndex(where: { $0.uid == uid }) else { return }
        change(&roster[index])
        // Persist after every fetch phase, not only when the view happens to
        // observe the array change, so a kill mid-load keeps the last result.
        PlayerRosterStore.save(roster)
    }


    private func remove(_ uid: String) {
        tasks[uid]?.cancel()
        tasks[uid] = nil
        roster.removeAll { $0.uid == uid }
        if selectedUID == uid {
            selectedUID = roster.first?.uid
        }
        if lastUID == uid, selectedUID == nil {
            lastUID = ""
        }
        PlayerRosterStore.save(roster)
    }

    private static func parseUIDs(_ raw: String) -> [String] {
        let tokens = raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
        var seen = Set<String>()
        return tokens.filter { token in
            (8...20).contains(token.count) && seen.insert(token).inserted
        }
    }
}

// MARK: - Item detail

/// Every item opens natively. Nothing on this screen hands the player off to a
/// website, so the sheet shows only what the public profile already published.
struct PlayerItemDetailSheet: View {
    let item: PlayerOutfitItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                            .fill(AppPalette.raised)
                        preview
                            .padding(AppSpacing.xl)
                    }
                    .frame(height: 200)

                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text(item.name)
                            .font(AppType.display())
                            .foregroundStyle(AppPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: AppSpacing.s) {
                            AppStatChip(
                                icon: "square.grid.2x2",
                                text: language.text(item.slot.localizationKey)
                            )
                            if !item.rarity.isEmpty {
                                AppStatChip(icon: "sparkles", text: item.rarity)
                            }
                            if item.likes > 0 {
                                AppStatChip(icon: "heart.fill", text: item.likes.formatted())
                            }
                        }
                    }

                    Text(language.text("intel.item_note"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.l)
            }
            .background(AppPalette.canvas)
            .navigationTitle(language.text("intel.outfit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let url = item.iconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(AppPalette.textTertiary)
            .accessibilityHidden(true)
    }
}
