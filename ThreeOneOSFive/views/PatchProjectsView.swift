import SwiftUI
import UIKit

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var store = PatchProjectStore()
    @State private var showCreate = false
    @State private var selectedID: UUID?
    @State private var openID: UUID?
    @State private var zoneFilter: PatchAimZone?
    @State private var toast: AppToastMessage?
    @AppStorage("hero_character_model") private var heroCharacterRaw = HeroCharacterModel.rouk.rawValue

    init() {
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.l) {
                    patchControlCard
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 480)
                        .frame(maxWidth: .infinity)
                        .appCinematicReveal(delay: 0.04)
                    librarySection
                        .appCinematicReveal(delay: 0.10)
                }
                .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 1040)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.screenInset)
                .padding(.top, AppSpacing.s)
                .padding(.bottom, AppSpacing.xxl)
            }
            .background(AppPremiumBackdrop())
            .appToast($toast)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { openID != nil },
                set: { if !$0 { openID = nil } }
            )) {
                if let detailID = openID {
                    PatchProjectDetailView(store: store, projectID: detailID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel(language.text("patch.add"))
                }
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
                PatchUnlockView(store: store)
            }
            .alert(item: $store.alert) { alert in
                Alert(
                    title: Text(language.text(alert.titleKey)),
                    message: Text(alert.message(language: language)),
                    dismissButton: .default(Text(language.text("common.ok")))
                )
            }
            .task {
                store.installBundledResources(credentials: licenseManager.patchFeedCredentials())
            }
        }
    }

    // MARK: - Control card

    private var heroCharacter: HeroCharacterModel {
        HeroCharacterModel(rawValue: heroCharacterRaw) ?? .rouk
    }

    private var heroCharacterSelection: Binding<HeroCharacterModel> {
        Binding(
            get: { HeroCharacterModel(rawValue: heroCharacterRaw) ?? .rouk },
            set: { heroCharacterRaw = $0.rawValue }
        )
    }

    private var selectedItem: PatchLibraryItem? {
        guard let selectedID else { return nil }
        return store.items.first(where: { $0.id == selectedID })
    }

    private var selectedZone: PatchAimZone? {
        guard let selectedItem else { return nil }
        return PatchAimZone.resolve(projectName: Self.displayName(of: selectedItem))
    }

    private var workspaceCount: Int {
        store.items.filter { $0.summary.schemaVersion >= 2 }.count
    }

    private var filteredItems: [PatchLibraryItem] {
        guard let zoneFilter else { return store.items }
        return store.items.filter {
            PatchAimZone.resolve(projectName: Self.displayName(of: $0)) == zoneFilter
        }
    }

    private static func displayName(of item: PatchLibraryItem) -> String {
        item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent
    }

    /// The stage, the character switch and the one action that matters. A
    /// package is only a name until it is placed on the body, so selection
    /// happens here and the detail sheet is one tap away instead of the tile's
    /// whole surface.
    private var patchControlCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.s) {
                Circle()
                    .fill(AppPalette.brand)
                    .frame(width: 6, height: 6)
                    .shadow(color: AppPalette.brand.opacity(0.8), radius: 5)
                Text(language.text("patch.control.title"))
                    .font(AppType.label().weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer(minLength: AppSpacing.s)
                HeroCharacterSwitcher(selection: heroCharacterSelection)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.top, AppSpacing.m)
            .padding(.bottom, AppSpacing.s)

            PatchBodyStageView(model: heroCharacter, zone: selectedZone ?? zoneFilter) { zone in
                AppHaptics.select()
                withAnimation(.easeOut(duration: AppMotion.control)) {
                    zoneFilter = zone
                    if zone != nil {
                        selectedID = nil
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
            .padding(.horizontal, AppSpacing.m)

            HStack(spacing: AppSpacing.s) {
                Text(language.text("patch.stage.footer"))
                    .font(AppType.label().weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppPalette.brand)
                Text(footerDetail)
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: AppSpacing.xs)

                Button {
                    guard let selectedItem else { return }
                    AppHaptics.tap()
                    openID = selectedItem.id
                } label: {
                    HStack(spacing: 6) {
                        Text(language.text("patch.stage.open"))
                            .font(AppType.label().weight(.bold))
                            .tracking(1.1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(selectedItem == nil ? AppPalette.textTertiary : AppPalette.canvas)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background {
                        if selectedItem == nil {
                            Capsule().fill(AppPalette.raised)
                        } else {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [AppPalette.brand, AppPalette.brand.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .overlay {
                        Capsule().strokeBorder(
                            selectedItem == nil ? AppPalette.hairline.opacity(0.6) : Color.white.opacity(0.28),
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(AppPressButtonStyle())
                .disabled(selectedItem == nil)
                .accessibilityLabel(language.text("patch.stage.open"))
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.top, AppSpacing.m)
            .padding(.bottom, AppSpacing.m)
        }
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .strokeBorder(AppPalette.hairline.opacity(0.5), lineWidth: 1)
        }
    }

    private var footerDetail: String {
        let count = "\(store.items.count) \(language.text("patch.stage.packages"))"
        guard let selectedItem else { return count }
        return count + " · " + Self.displayName(of: selectedItem).uppercased()
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.s) {
                Text(language.text("patch.library"))
                    .font(AppType.section())
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer(minLength: AppSpacing.s)
                Button {
                    AppHaptics.tap()
                    store.reload()
                    toast = AppToastMessage(
                        text: language.text("patch.library.refreshed", Int64(store.items.count)),
                        icon: "arrow.clockwise"
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                        .frame(width: 34, height: 34)
                        .background(AppPalette.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AppPalette.hairline.opacity(0.6), lineWidth: 1)
                        }
                }
                .buttonStyle(AppPressButtonStyle())
                .accessibilityLabel(language.text("patch.library.refresh"))
            }

            HStack(spacing: AppSpacing.xl) {
                libraryStat(value: store.items.count, key: "patch.library.packages")
                libraryStat(value: workspaceCount, key: "patch.library.workspaces")
                Spacer(minLength: 0)
            }

            if let zoneFilter {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: zoneFilter.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                    Text(language.text(zoneFilter.titleKey))
                        .font(AppType.label().weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("\(filteredItems.count)")
                        .font(AppType.label())
                        .foregroundStyle(AppPalette.textTertiary)
                        .monospacedDigit()
                    Spacer(minLength: AppSpacing.s)
                    Button {
                        AppHaptics.tap()
                        withAnimation(.easeOut(duration: AppMotion.control)) {
                            self.zoneFilter = nil
                        }
                    } label: {
                        Text(language.text("patch.filter.clear"))
                            .font(AppType.label().weight(.semibold))
                            .foregroundStyle(AppPalette.brand)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.xs)
                .background(AppPalette.raised, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppPalette.brand.opacity(0.3), lineWidth: 1)
                }
            }

            if store.items.isEmpty && !store.isBusy {
                emptyState
            } else if filteredItems.isEmpty {
                Text(language.text("patch.filter.empty"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.xl)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: AppSpacing.m),
                        count: horizontalSizeClass == .regular ? 3 : 2
                    ),
                    spacing: AppSpacing.m
                ) {
                    ForEach(filteredItems) { item in
                        itemTile(item).appCinematicReveal(
                            delay: min(Double(filteredItems.firstIndex(where: { $0.id == item.id }) ?? 0) * 0.045, 0.32)
                        ).appDepthLayer(.hero)
                    }
                }
            }
        }
    }

    private func libraryStat(value: Int, key: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            AppRollingNumber(value: value, size: 22)
            Text(language.text(key))
                .font(AppType.label().weight(.bold))
                .tracking(1.1)
                .foregroundStyle(AppPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func itemTile(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button {
                AppHaptics.tap()
                store.requestUnlock(for: item)
            } label: {
                PatchProjectTile(
                    item: item,
                    language: language,
                    isSelected: false,
                    unavailable: store.unavailableTargets[item.id] ?? []
                )
            }
            .buttonStyle(AppPressButtonStyle())
            .contextMenu { deleteButton(for: item) }
        } else {
            Button {
                AppHaptics.select()
                withAnimation(.easeOut(duration: AppMotion.control)) {
                    if selectedID == item.id {
                        openID = item.id
                    } else {
                        selectedID = item.id
                    }
                }
            } label: {
                PatchProjectTile(
                    item: item,
                    language: language,
                    isSelected: selectedID == item.id,
                    unavailable: store.unavailableTargets[item.id] ?? []
                )
            }
            .buttonStyle(AppPressButtonStyle())
            .contextMenu { deleteButton(for: item) }
        }
    }

    @ViewBuilder
    private func deleteButton(for item: PatchLibraryItem) -> some View {
        Button(role: .destructive) {
            store.delete(item)
        } label: {
            Label(language.text("browser.delete"), systemImage: "trash")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("patch.empty_title"))
                .font(.headline)
            Text(language.text("patch.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

}

private struct PatchProjectTile: View {
    let item: PatchLibraryItem
    let language: AppLanguage
    var isSelected: Bool = false
    var unavailable: [String] = []

    private var zone: PatchAimZone {
        PatchAimZone.resolve(
            projectName: item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                AppRowIcon(
                    systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill",
                    symbolSize: 15,
                    frameSize: 30
                )
                .background(
                    AppPalette.brand.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(AppPalette.brand.opacity(0.18), lineWidth: 1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                } else if item.summary.isPasswordProtected {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.textTertiary)
                        .accessibilityLabel(language.text("patch.password_protected"))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock")
                     : language.text(
                        item.summary.schemaVersion >= 2 ? "patch.workspace_items_count" : "patch.rules_count",
                        Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
                     ))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
            }

            if !unavailable.isEmpty {
                Label(
                    language.text("patch.target_unavailable", unavailable.joined(separator: ", ")),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppPalette.amber)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: zone.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(language.text(zone.titleKey))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? AppPalette.brand.opacity(0.14) : Color.white.opacity(0.04))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(AppSpacing.m)
        .background(isSelected ? AppPalette.brand.opacity(0.10) : AppPalette.raised)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .strokeBorder(
                    isSelected ? AppPalette.brand.opacity(0.55) : AppPalette.hairline.opacity(0.45),
                    lineWidth: 1
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(language.text("patch.password_once_message"))
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?
    @State private var transaction: PatchTransactionProgress?
    @State private var showPreview = false
    @State private var previewLeading: PatchPayloadImage?
    @State private var previewTrailing: PatchPayloadImage?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    private var imageRules: [PatchRule] {
        (item?.project?.rules ?? []).filter { $0.payloadLooksLikeImage }
    }

    private var previewPairAvailable: Bool {
        imageRules.count >= 2
    }

    private func preparePreview() {
        let rules = imageRules
        guard rules.count >= 2,
              let first = UIImage(data: rules[0].replacementData),
              let second = UIImage(data: rules[1].replacementData) else { return }
        previewLeading = PatchPayloadImage(image: first, label: rules[0].replacementFilename)
        previewTrailing = PatchPayloadImage(image: second, label: rules[1].replacementFilename)
        showPreview = true
    }

    private func localizedMessage(_ error: PatchPackageError) -> String {
        if let argument = error.localizationArgument {
            return language.text(error.localizationKey, argument)
        }
        return language.text(error.localizationKey)
    }

    var body: some View {
        List {
            if let item, let project = item.project {
                if isWorkspaceProject {
                    Section {
                        ForEach(project.allBundleIdentifiers, id: \.self) { bundleID in
                            Label {
                                Text(bundleID)
                                    .font(.subheadline.monospaced())
                            } icon: {
                                Image(systemName: "app.dashed")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        LabeledContent(language.text("patch.files")) {
                            Text("\(project.rules.count)")
                        }
                        LabeledContent(language.text("patch.folders")) {
                            Text("\(project.directories.count)")
                        }
                        if let workspaceURL = item.workspaceURL {
                            NavigationLink {
                                FileBrowserView(
                                    containerPath: workspaceURL.path,
                                    title: project.name,
                                    bundleID: nil
                                )
                            } label: {
                                Label(
                                    language.text("patch.open_workspace"),
                                    systemImage: "folder"
                                )
                            }
                        }
                    } header: {
                        Text(language.text("patch.workspace"))
                    } footer: {
                        Text(language.text("patch.workspace_detail_footer"))
                    }
                } else {
                    Section {
                        ForEach(project.rules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                HStack(spacing: 10) {
                                    ruleSummary(rule)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(language.text("patch.edit_rule_hint"))
                        }
                    } header: {
                        Text(language.text("patch.rules"))
                    } footer: {
                        Text(language.text("patch.legacy_footer"))
                    }
                }

                if previewPairAvailable {
                    Section(language.text("patch.preview.title")) {
                        Button(action: preparePreview) {
                            actionLabel("patch.preview.open", systemImage: "rectangle.split.2x1")
                        }
                        .disabled(isWorking)
                    }
                }

                Section(language.text("patch.password")) {
                    HStack(spacing: 12) {
                        Image(systemName: item.summary.isPasswordProtected ? "lock.fill" : "lock.open")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)
                        Text(language.text(item.summary.isPasswordProtected
                            ? "patch.password_locked"
                            : "patch.no_password"))
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        showApplyConfirmation = true
                    } label: {
                        actionLabel("patch.apply", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(isWorking)

                    if receipt != nil {
                        Button(role: .destructive) {
                            showRestoreConfirmation = true
                        } label: {
                            actionLabel("patch.restore", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(isWorking)
                    }
                } footer: {
                    Text(language.text("patch.apply_footer"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if isWorking {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.08)
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.large)
                            Text(language.text("patch.operation_in_progress"))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 220)
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(16)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .navigationTitle(item?.project?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let transaction {
                PatchTransactionOverlay(progress: transaction) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.transaction = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            if let previewLeading, let previewTrailing {
                PatchPayloadPreview(leading: previewLeading, trailing: previewTrailing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isWorkspaceProject {
                    Button(language.text("patch.edit")) { showEditor = true }
                        .disabled(isWorking || item?.project == nil)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let item, let project = item.project {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) { apply() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_confirm_title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore"), role: .destructive) { restore() }
            Button(language.text("common.cancel"), role: .cancel) {}
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(language.text(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let item, let baseProject = item.project else { return }
        isWorking = true
        transaction = PatchTransactionProgress(
            title: language.text("patch.apply"),
            done: 0,
            total: max(1, baseProject.rules.count),
            phase: .running
        )
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project) { done, total in
                    Task { @MainActor in
                        guard var current = self.transaction else { return }
                        current.done = done
                        current.total = max(1, total)
                        self.transaction = current
                    }
                }
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .success(language.text("patch.applied_message"))
                        self.transaction = current
                    }
                    PatchAudioFeedback.play(enabled: true)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .failure(localizedMessage(error))
                        self.transaction = current
                    }
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .failure(language.text("patch.error.apply"))
                        self.transaction = current
                    }
                }
            }
        }
    }

    private func restore() {
        guard let receipt, let item else { return }
        isWorking = true
        transaction = PatchTransactionProgress(
            title: language.text("patch.restore"),
            done: 0,
            total: max(1, item.project?.rules.count ?? 1),
            phase: .running
        )
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt) { done, total in
                    Task { @MainActor in
                        guard var current = self.transaction else { return }
                        current.done = done
                        current.total = max(1, total)
                        self.transaction = current
                    }
                }
                await MainActor.run {
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .success(language.text("patch.restored_message"))
                        self.transaction = current
                    }
                    PatchAudioFeedback.play(enabled: false)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .failure(localizedMessage(error))
                        self.transaction = current
                    }
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    if var current = self.transaction {
                        current.phase = .failure(language.text("patch.error.restore"))
                        self.transaction = current
                    }
                }
            }
        }
    }
}
