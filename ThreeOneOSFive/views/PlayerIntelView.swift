import SwiftUI
import WebKit

/// Player lookup for Free Fire IDs. Each added ID loads its public profile and
/// equipped set; every player keeps its own row, and the selected player's
/// garments are downloaded onto the 3D character.
struct PlayerIntelView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("hero_character_model") private var heroModelRaw = HeroCharacterModel.rouk.rawValue

    @State private var roster: [PlayerIntelEntry] = PlayerRosterStore.load()
    @State private var selectedUID: String?
    @State private var query = ""
    @State private var addErrorKey: String?
    @State private var activeItem: PlayerOutfitItem?
    @State private var isVisible = false
    @State private var tasks: [String: Task<Void, Never>] = [:]
    @FocusState private var searchFocused: Bool

    private var isBusy: Bool { roster.contains(where: \.isLoading) }

    private var selectedEntry: PlayerIntelEntry? {
        if let selectedUID,
           let match = roster.first(where: { $0.uid == selectedUID }) {
            return match
        }
        return roster.first
    }

    private var modelBinding: Binding<HeroCharacterModel> {
        Binding(
            get: { HeroCharacterModel(rawValue: heroModelRaw) ?? .rouk },
            set: { heroModelRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBar.appCinematicReveal(delay: 0.02)
                        addPanel.appCinematicReveal(delay: 0.08)

                        if !roster.isEmpty {
                            rosterPanel.appCinematicReveal(delay: 0.10)
                        }

                        content.appCinematicReveal(delay: 0.14)

                        footer.appCinematicReveal(delay: 0.26)
                    }
                    .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 900)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
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
            isVisible = true
            if selectedUID == nil || !roster.contains(where: { $0.uid == selectedUID }) {
                selectedUID = roster.first?.uid
            }
        }
        .onDisappear {
            isVisible = false
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
        }
        .onChange(of: roster) { updated in
            PlayerRosterStore.save(updated)
        }
        .sheet(item: $activeItem) { item in
            PlayerItemWebSheet(item: item)
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: AppSpacing.m) {
            AppLogo(size: horizontalSizeClass == .compact ? 38 : 46)
                .padding(3)
                .background(
                    AppPalette.raised.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("intel.title"))
                    .font(.system(
                        size: horizontalSizeClass == .compact ? 17 : 20,
                        weight: .black,
                        design: .rounded
                    ))
                    .tracking(horizontalSizeClass == .compact ? 1.0 : 1.5)
                    .foregroundStyle(AppPalette.textPrimary)
                Text(language.text("intel.kicker"))
                    .font(AppType.label())
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
            }

            Spacer(minLength: AppSpacing.xs)
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.panel)
    }

    // MARK: - Add players

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
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
            .frame(minHeight: 46)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )

            AppActionButton(
                title: language.text("intel.add_player"),
                icon: "person.badge.plus",
                isEnabled: !trimmedQuery.isEmpty,
                action: addPlayers
            )

            Text(language.text("intel.add_hint"))
                .font(AppType.meta())
                .foregroundStyle(AppPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let addErrorKey {
                Text(language.text(addErrorKey))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    // MARK: - Roster

    private var rosterPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .center, spacing: AppSpacing.s) {
                AppSectionHeader(
                    icon: "person.2.fill",
                    title: language.text("intel.roster"),
                    subtitle: language.text("intel.roster_count", roster.count)
                )

                Spacer(minLength: 0)

                Button {
                    AppHaptics.tap()
                    refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isBusy ? AppPalette.textTertiary : AppTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(AppPalette.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(language.text("intel.refresh_all"))
            }

            ForEach(roster) { entry in
                rosterRow(entry)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func rosterRow(_ entry: PlayerIntelEntry) -> some View {
        let isSelected = selectedEntry?.uid == entry.uid

        return HStack(spacing: AppSpacing.s) {
            Button {
                if entry.profile == nil, entry.errorKey != nil {
                    startLoad(entry.uid)
                } else {
                    AppHaptics.select()
                    selectedUID = entry.uid
                }
            } label: {
                HStack(spacing: AppSpacing.s) {
                    rosterAvatar(entry)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.profile?.nickname ?? entry.uid)
                            .font(AppType.body().weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .lineLimit(1)

                        Text(rosterDetail(entry))
                            .font(AppType.meta())
                            .foregroundStyle(entry.errorKey == nil ? AppPalette.textTertiary : AppPalette.amber)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if entry.isLoading {
                        ProgressView()
                            .tint(AppTheme.accent)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    } else if entry.errorKey != nil {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppPalette.amber)
                    }
                }
                .padding(AppSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? AppPalette.raised : AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.profile?.nickname ?? entry.uid), \(rosterDetail(entry))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                AppHaptics.tap()
                remove(entry.uid)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(AppPalette.canvas, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("intel.remove_player"))
        }
    }

    @ViewBuilder
    private func rosterAvatar(_ entry: PlayerIntelEntry) -> some View {
        let shape = Circle()

        if let url = entry.profile?.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialAvatar(entry)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
        } else {
            initialAvatar(entry)
                .clipShape(shape)
                .accessibilityHidden(true)
        }
    }

    private func initialAvatar(_ entry: PlayerIntelEntry) -> some View {
        ZStack {
            Circle().fill(AppPalette.canvas)
            Text(String(entry.profile?.nickname.prefix(1) ?? entry.uid.prefix(1)))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.textSecondary)
        }
    }

    private func rosterDetail(_ entry: PlayerIntelEntry) -> String {
        if let key = entry.errorKey {
            return language.text(key)
        }
        if entry.isLoading, entry.profile == nil {
            return language.text("intel.loading_player")
        }
        guard let profile = entry.profile else {
            return language.text("intel.loading_player")
        }

        var parts: [String] = []
        if !profile.region.isEmpty { parts.append(profile.region) }
        parts.append("\(language.text("intel.level")) \(profile.level)")
        parts.append(language.text("intel.outfit_count", entry.items.count))
        return parts.joined(separator: " · ")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let entry = selectedEntry {
            if let profile = entry.profile {
                VStack(spacing: AppSpacing.l) {
                    profilePanel(profile)
                    PlayerOutfitStage(
                        items: entry.items,
                        model: modelBinding,
                        isActive: isVisible,
                        onOpenItem: { activeItem = $0 }
                    )
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
        VStack(alignment: .leading, spacing: AppSpacing.l) {
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

                avatar(profile)
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
        .appPanel(radius: AppRadius.panel)
    }

    @ViewBuilder
    private func avatar(_ profile: PlayerIntelProfile) -> some View {
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
            .frame(width: 64, height: 64)
            .clipShape(shape)
            .overlay(shape.strokeBorder(AppTheme.accent.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
        } else {
            avatarPlaceholder
                .frame(width: 64, height: 64)
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
            AppSectionHeader(
                icon: "tshirt.fill",
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
                    columns: [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)],
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
                        .disabled(item.pageURL == nil)
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func itemCard(_ item: PlayerOutfitItem) -> some View {
        HStack(spacing: AppSpacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppPalette.canvas)

                if let url = item.iconURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(3)
                        default:
                            itemGlyph
                        }
                    }
                } else {
                    itemGlyph
                }
            }
            .frame(width: 44, height: 44)

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

            Spacer(minLength: 0)

            if item.has3D {
                Image(systemName: "cube")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.canvas,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.has3D ? language.text("intel.open_3d") : "")
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
        .appPanel(radius: AppRadius.panel)
        .accessibilityElement(children: .combine)
    }

    private var idlePanel: some View {
        AppEmptyState(
            icon: "person.text.rectangle",
            title: language.text("intel.empty_title"),
            message: language.text("intel.empty_message")
        )
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
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
        .appPanel(radius: AppRadius.panel)
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.s) {
            if let updated = updatedText {
                Text(updated)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
            }
            if let url = selectedEntry?.profile?.profileURL {
                Link(destination: url) {
                    Label(language.text("intel.open_profile"), systemImage: "arrow.up.right.square")
                        .font(AppType.label())
                        .foregroundStyle(AppTheme.accent)
                }
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
        query = ""
        searchFocused = false

        var added: [String] = []
        for uid in uids where !roster.contains(where: { $0.uid == uid }) {
            roster.append(
                PlayerIntelEntry(
                    uid: uid,
                    profile: nil,
                    items: [],
                    outfitFailed: false,
                    errorKey: nil,
                    isLoading: true
                )
            )
            added.append(uid)
        }

        guard !added.isEmpty else { return }
        if selectedUID == nil {
            selectedUID = added[0]
        }
        for uid in added {
            startLoad(uid)
        }
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
                let outfit = try await PlayerOutfitScraper.shared.outfit(uid: uid)
                guard !Task.isCancelled else { return }
                update(uid) { entry in
                    entry.items = outfit
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
    }

    private func refreshAll() {
        for entry in roster {
            startLoad(entry.uid)
        }
    }

    private func remove(_ uid: String) {
        tasks[uid]?.cancel()
        tasks[uid] = nil
        roster.removeAll { $0.uid == uid }
        if selectedUID == uid {
            selectedUID = roster.first?.uid
        }
    }

    private static func parseUIDs(_ raw: String) -> [String] {
        let tokens = raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
        var seen = Set<String>()
        return tokens.filter { token in
            (8...20).contains(token.count) && seen.insert(token).inserted
        }
    }
}

// MARK: - Item 3D viewer

/// The catalogue page owns the garment model. The app cannot bundle every
/// outfit, so the item's own 3D viewer opens here, inside the app.
struct PlayerItemWebSheet: View {
    let item: PlayerOutfitItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Group {
                if let url = item.pageURL {
                    PlayerItemWebView(url: url)
                } else {
                    AppEmptyState(
                        icon: "cube.transparent",
                        title: item.name,
                        message: language.text("intel.error_outfit")
                    )
                    .padding(AppSpacing.l)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.close")) { dismiss() }
                }
            }
        }
    }
}

private struct PlayerItemWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        _ = webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
            (function () {
              var section = document.getElementById('modelo-3d');
              if (section) { section.scrollIntoView({ block: 'start' }); }
              var open = document.querySelector('[data-ffwiki-model-open]');
              if (open && !open.disabled) { open.click(); }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
