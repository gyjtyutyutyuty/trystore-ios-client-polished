import SwiftUI

/// Storage console. Scans every installed app container for disposable cache and
/// temporary data, then purges it through `LimitedCleanerService`, which is
/// restricted to `Library/Caches` and `tmp` inside each container. Documents and
/// saves are never touched.
struct CleanerView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var records: [CleanerAppRecord] = []
    @State private var selectedBundleIDs: Set<String> = []
    @State private var searchText = ""
    @State private var sortLargestFirst = true
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var scannedAppCount = 0
    @State private var hasLoaded = false
    @State private var scanID = UUID()

    @State private var progress: Double = 0
    @State private var stageLabel = ""
    @State private var showProgressCard = false
    @State private var freedBytes: Int64 = 0
    @State private var removedItems = 0
    @State private var stalledItems = 0
    @State private var progressTask: Task<Void, Never>?

    // MARK: - Derived state

    private var visibleRecords: [CleanerAppRecord] {
        let matching: [CleanerAppRecord]
        if searchText.isEmpty {
            matching = records
        } else {
            let query = searchText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            matching = records.filter {
                $0.app.displayName.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).contains(query) || $0.app.bundleID.lowercased().contains(query.lowercased())
            }
        }

        return CleanerCatalog.sorted(
            matching,
            order: sortLargestFirst ? .largestFirst : .smallestFirst,
            size: { $0.usage.totalBytes },
            displayName: { $0.app.displayName },
            stableID: { $0.id }
        )
    }

    private var reclaimableBytes: Int64 {
        records.reduce(0) { $0 + $1.usage.totalBytes }
    }

    private var selectedBytes: Int64 {
        records.reduce(0) { total, record in
            total + (selectedBundleIDs.contains(record.id) ? record.usage.totalBytes : 0)
        }
    }

    private var cacheBytes: Int64 {
        records.reduce(0) { $0 + $1.usage.cacheBytes }
    }

    private var temporaryBytes: Int64 {
        records.reduce(0) { $0 + $1.usage.temporaryBytes }
    }

    private var removableItemCount: Int {
        records.reduce(0) { $0 + $1.usage.removableItemCount }
    }

    private var reclaimRatio: Double {
        guard reclaimableBytes > 0 else { return 0 }
        return min(1, Double(selectedBytes) / Double(reclaimableBytes))
    }

    private var isBusy: Bool {
        isScanning || isCleaning
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppPremiumBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.l) {
                        topBar.appCinematicReveal(delay: 0.02)
                        heroPanel.appCinematicReveal(delay: 0.08)
                        storageBar.appCinematicReveal(delay: 0.11)
                        breakdownPanel.appCinematicReveal(delay: 0.14)
                        appsPanel.appCinematicReveal(delay: 0.20)
                        footerNote.appCinematicReveal(delay: 0.26)
                    }
                    .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 980)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenInset)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }

                if showProgressCard {
                    progressOverlay
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppTheme.accent)
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: AppSpacing.m) {
            AppLogo(size: horizontalSizeClass == .compact ? 38 : 46)
                .padding(3)
                .background(AppPalette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("cleaner.console.title"))
                    .font(.system(size: horizontalSizeClass == .compact ? 17 : 20, weight: .black, design: .rounded))
                    .tracking(horizontalSizeClass == .compact ? 1.0 : 1.5)
                    .foregroundStyle(AppPalette.textPrimary)
                Text(language.text("cleaner.console.subtitle"))
                    .font(AppType.label())
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
            }

            Spacer(minLength: AppSpacing.xs)

            Button(action: reload) {
                ZStack {
                    Circle()
                        .fill(AppPalette.raised.opacity(0.55))
                    Circle()
                        .stroke(AppPalette.hairline.opacity(0.65), lineWidth: 1)
                    if isScanning {
                        ProgressView()
                            .tint(AppTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.textPrimary)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(AppPressButtonStyle())
            .disabled(isBusy)
            .accessibilityLabel(language.text("cleaner.rescan"))
        }
        .padding(AppSpacing.m)
        .appPanel(radius: AppRadius.panel, tint: AppTheme.accent)
    }

    // MARK: - Composition

    /// One bar answers "what is actually reclaimable" before the panel below
    /// lists it. Cache, temporary files and everything else share the width.
    private var storageBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let total = CGFloat(max(1, reclaimableBytes))
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(AppPalette.brand)
                        .frame(width: max(0, width * CGFloat(cacheBytes) / total - 1), height: 8)
                    Rectangle()
                        .fill(AppPalette.amber)
                        .frame(width: max(0, width * CGFloat(temporaryBytes) / total - 1), height: 8)
                    Rectangle()
                        .fill(AppPalette.hairline.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: AppSpacing.l) {
                barLegend(key: "cleaner.bar.cache", bytes: cacheBytes, tint: AppPalette.brand)
                barLegend(key: "cleaner.bar.temp", bytes: temporaryBytes, tint: AppPalette.amber)
                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
        .accessibilityElement(children: .combine)
    }

    private func barLegend(key: String, bytes: Int64, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(language.text(key))
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(AppPalette.textTertiary)
            Text(sizeText(bytes))
                .font(AppType.label())
                .foregroundStyle(AppPalette.textSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - Hero

    private var heroPanel: some View {
        VStack(spacing: AppSpacing.l) {
            HStack(alignment: .center, spacing: AppSpacing.l) {
                AppRingGauge(
                    progress: reclaimRatio,
                    value: sizeText(selectedBytes),
                    caption: language.text("cleaner.reclaimable"),
                    tint: AppPalette.mint,
                    diameter: horizontalSizeClass == .compact ? 128 : 146
                )

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    metricRow(icon: "square.stack.3d.up.fill", label: language.text("cleaner.metric.apps"), value: "\(records.count)")
                    metricRow(icon: "trash.fill", label: language.text("cleaner.metric.items"), value: "\(removableItemCount)")
                    metricRow(icon: "checkmark.circle.fill", label: language.text("cleaner.metric.selected"), value: "\(selectedBundleIDs.count)")
                }
            }

            AppActionButton(
                title: isScanning
                    ? language.text("cleaner.button.scanning")
                    : language.text(selectedBundleIDs.isEmpty ? "cleaner.button.none" : "cleaner.button.clean"),
                icon: isScanning ? "rays" : "sparkles",
                tint: AppPalette.mint,
                isEnabled: !selectedBundleIDs.isEmpty && !isBusy,
                action: beginClean
            )
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func metricRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 16)
            Text(label)
                .font(AppType.label())
                .tracking(0.6)
                .foregroundStyle(AppPalette.textTertiary)
            Spacer(minLength: AppSpacing.s)
            Text(value)
                .font(AppType.digits(13))
                .foregroundStyle(AppPalette.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Breakdown

    private var breakdownPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            AppSectionHeader(icon: "chart.bar.fill", title: language.text("cleaner.section.breakdown"), subtitle: language.text("cleaner.section.breakdown_sub"))

            breakdownBar(label: language.text("cleaner.label.cache"), bytes: cacheBytes, tint: AppPalette.mint)
            breakdownBar(label: language.text("cleaner.label.temporary"), bytes: temporaryBytes, tint: AppPalette.blue)

            HStack(spacing: AppSpacing.s) {
                AppStatChip(icon: "shield.lefthalf.filled", text: language.text("cleaner.chip.caches_only"), tint: AppPalette.mint)
                AppStatChip(icon: "doc.fill", text: language.text("cleaner.chip.saves_kept"), tint: AppPalette.blue)
                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func breakdownBar(label: String, bytes: Int64, tint: Color) -> some View {
        let denominator = max(reclaimableBytes, 1)
        let fraction = min(1, Double(bytes) / Double(denominator))

        return VStack(spacing: 7) {
            HStack(spacing: AppSpacing.s) {
                Text(label)
                    .font(AppType.label())
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.textSecondary)
                Spacer(minLength: AppSpacing.s)
                Text(sizeText(bytes))
                    .font(AppType.digits(12))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppPalette.hairline.opacity(0.55))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.65)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                        .shadow(color: tint.opacity(0.45), radius: 8)
                }
            }
            .frame(height: 7)
            .animation(reduceMotion ? nil : AppMotion.surface, value: fraction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(sizeText(bytes))")
    }

    // MARK: - Apps

    private var appsPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.s) {
                AppSectionHeader(icon: "square.grid.2x2.fill", title: language.text("cleaner.section.apps"), subtitle: isScanning ? language.text("cleaner.apps.scanned", Int64(scannedAppCount)) : language.text("cleaner.apps.with_cache", Int64(records.count)))
                Spacer(minLength: 0)
            }

            if records.count > 2 {
                AppSearchField(
                    text: $searchText,
                    prompt: language.text("cleaner.search"),
                    clearLabel: language.text("common.clear")
                )
            }

            HStack(spacing: AppSpacing.s) {
                selectionChip(title: language.text("cleaner.select.all"), isOn: !records.isEmpty && selectedBundleIDs.count == records.count) {
                    selectedBundleIDs = Set(records.map(\.id))
                }
                selectionChip(title: language.text("cleaner.select.none"), isOn: selectedBundleIDs.isEmpty) {
                    selectedBundleIDs.removeAll()
                }
                Spacer(minLength: 0)
                Button {
                    AppHaptics.select()
                    sortLargestFirst.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: sortLargestFirst ? "arrow.down" : "arrow.up")
                            .font(.system(size: 10, weight: .black))
                        Text(language.text(sortLargestFirst ? "cleaner.sort.largest" : "cleaner.sort.smallest"))
                            .font(AppType.label())
                            .tracking(0.5)
                    }
                    .foregroundStyle(AppPalette.textSecondary)
                    .padding(.horizontal, AppSpacing.m)
                    .frame(height: 30)
                    .background(AppPalette.raised.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(AppPalette.hairline.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(AppPressButtonStyle())
                .disabled(isBusy)
            }

            if visibleRecords.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: AppSpacing.s),
                        count: horizontalSizeClass == .regular ? 2 : 1
                    ),
                    spacing: AppSpacing.s
                ) {
                    ForEach(visibleRecords) { record in
                        appRow(record)
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .appPanel(radius: AppRadius.panel)
    }

    private func selectionChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.select()
            action()
        } label: {
            Text(title)
                .font(AppType.label())
                .tracking(0.6)
                .foregroundStyle(isOn ? Color(red: 0.02, green: 0.07, blue: 0.07) : AppPalette.textSecondary)
                .padding(.horizontal, AppSpacing.m)
                .frame(height: 30)
                .background(
                    isOn
                        ? AnyShapeStyle(LinearGradient(colors: [AppPalette.mint, AppPalette.mint.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(AppPalette.raised.opacity(0.55)),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isOn ? Color.white.opacity(0.24) : AppPalette.hairline.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(isBusy)
    }

    private func appRow(_ record: CleanerAppRecord) -> some View {
        let isSelected = selectedBundleIDs.contains(record.id)

        return Button {
            AppHaptics.select()
            withAnimation(reduceMotion ? nil : AppMotion.tile) {
                if isSelected {
                    selectedBundleIDs.remove(record.id)
                } else {
                    selectedBundleIDs.insert(record.id)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.m) {
                BrowserAppIcon(app: record.app)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.app.displayName)
                        .font(AppType.body())
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                    Text(record.app.bundleID)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppPalette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: AppSpacing.xs)

                Text(sizeText(record.usage.totalBytes))
                    .font(AppType.digits(12))
                    .foregroundStyle(isSelected ? AppPalette.mint : AppPalette.textSecondary)
                    .monospacedDigit()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppPalette.mint : AppPalette.hairline)
            }
            .padding(.horizontal, AppSpacing.m)
            .frame(minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : AppPalette.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.70) : AppPalette.hairline.opacity(0.55), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(AppPressButtonStyle())
        .disabled(isBusy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.app.displayName), \(sizeText(record.usage.totalBytes))")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.s) {
            if isScanning {
                AppSkeletonList(rows: 4)
                Text(language.text("cleaner.scanning.title"))
                    .font(AppType.label())
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.textSecondary)
                Text(language.text("cleaner.scanning.detail", Int64(scannedAppCount)))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppPalette.mint)
                Text(language.text("cleaner.empty.title"))
                    .font(AppType.label())
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.textPrimary)
                Text(language.text("cleaner.empty.message"))
                    .font(AppType.meta())
                    .foregroundStyle(AppPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.l)
    }

    private var footerNote: some View {
        VStack(spacing: AppSpacing.m) {
            AppHairline()
            Text(language.text("cleaner.footer"))
                .font(AppType.label())
                .tracking(1.0)
                .foregroundStyle(AppPalette.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Progress card

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: AppSpacing.l) {
                HStack(spacing: AppSpacing.s) {
                    Circle()
                        .fill(isCleaning ? AppPalette.amber : AppPalette.mint)
                        .frame(width: 6, height: 6)
                        .shadow(color: (isCleaning ? AppPalette.amber : AppPalette.mint).opacity(0.9), radius: 6)
                    Text(language.text(isCleaning ? "cleaner.purge.in_progress" : "cleaner.purge.complete"))
                        .font(AppType.label())
                        .tracking(1.1)
                        .foregroundStyle(AppPalette.textSecondary)
                    Spacer(minLength: AppSpacing.s)
                    Text("\(Int(progress * 100))%")
                        .font(AppType.digits(13))
                        .foregroundStyle(AppPalette.textPrimary)
                        .monospacedDigit()
                }

                ZStack {
                    Circle()
                        .stroke(AppPalette.hairline.opacity(0.60), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: max(0.004, progress))
                        .stroke(
                            AngularGradient(
                                colors: [AppPalette.mint.opacity(0.45), AppPalette.mint, Color.white.opacity(0.9), AppPalette.mint],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: AppPalette.mint.opacity(0.55), radius: 16)
                        .animation(.linear(duration: 0.12), value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 54, weight: .black, design: .monospaced))
                            .foregroundStyle(AppPalette.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(language.text(isCleaning ? "cleaner.percent" : "cleaner.complete"))
                            .font(AppType.label())
                            .tracking(1.4)
                            .foregroundStyle(AppPalette.textTertiary)
                    }
                }
                .frame(width: 196, height: 196)

                VStack(spacing: 6) {
                    Text(stageLabel)
                        .font(AppType.label())
                        .tracking(1.0)
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isCleaning ? language.text("cleaner.reclaiming", sizeText(selectedBytes)) : language.text("cleaner.freed", sizeText(freedBytes)))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                }

                HStack(spacing: 3) {
                    ForEach(0..<14, id: \.self) { index in
                        Capsule()
                            .fill(Double(index) / 14.0 < progress ? AppPalette.mint : AppPalette.hairline.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                            .shadow(color: Double(index) / 14.0 < progress ? AppPalette.mint.opacity(0.7) : .clear, radius: 4)
                    }
                }

                if isCleaning {
                    Text(language.text("cleaner.keep_open"))
                        .font(AppType.meta())
                        .foregroundStyle(AppPalette.textTertiary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: AppSpacing.s) {
                        HStack(spacing: AppSpacing.s) {
                            resultChip(icon: "trash.fill", text: language.text("cleaner.removed_count", Int64(removedItems)))
                            resultChip(icon: "exclamationmark.triangle.fill", text: language.text("cleaner.locked_count", Int64(stalledItems)))
                        }
                        AppActionButton(title: language.text("cleaner.done"), icon: "checkmark", tint: AppPalette.mint) {
                            dismissProgress()
                        }
                    }
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.surface, AppPalette.canvas],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                AppPalette.mint.opacity(0.70),
                                AppPalette.hairline.opacity(0.35),
                                Color.white.opacity(0.35),
                                AppPalette.hairline.opacity(0.35),
                                AppPalette.mint.opacity(0.70)
                            ],
                            center: .center
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                Circle()
                    .fill(AppPalette.mint.opacity(0.30))
                    .frame(width: 190, height: 190)
                    .blur(radius: 60)
                    .offset(y: -80)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 30, y: 16)
            .padding(.horizontal, AppSpacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text(isCleaning ? "cleaner.progress.running" : "cleaner.progress.done"))
    }

    private func resultChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(AppPalette.textSecondary)
            Text(text)
                .font(AppType.label())
                .tracking(0.4)
                .foregroundStyle(AppPalette.textPrimary)
        }
        .padding(.horizontal, AppSpacing.m)
        .frame(height: 30)
        .background(AppPalette.raised.opacity(0.60), in: Capsule())
        .overlay(Capsule().stroke(AppPalette.hairline.opacity(0.55), lineWidth: 1))
    }

    // MARK: - Pipeline

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    private func reload() {
        guard !isBusy else { return }
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-cleaner-empty") {
            records = []
            selectedBundleIDs = []
            scannedAppCount = 388
            isScanning = false
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--simulate-cleaner-data") {
            let samples = [
                CleanerAppRecord(
                    app: InstalledApp(
                        bundleID: "com.dts.freefiremax",
                        name: "Free Fire MAX",
                        containerPath: "/tmp/FreeFire",
                        version: "",
                        icon: nil
                    ),
                    usage: LimitedCleanerUsage(
                        cacheBytes: 412_549_376,
                        temporaryBytes: 38_582_912,
                        removableItemCount: 1_284
                    )
                ),
                CleanerAppRecord(
                    app: InstalledApp(
                        bundleID: "com.lemon.lvoverseas",
                        name: "CapCut",
                        containerPath: "/tmp/CapCut",
                        version: "",
                        icon: nil
                    ),
                    usage: LimitedCleanerUsage(
                        cacheBytes: 184_549_376,
                        temporaryBytes: 12_582_912,
                        removableItemCount: 284
                    )
                ),
                CleanerAppRecord(
                    app: InstalledApp(
                        bundleID: "com.apple.Maps",
                        name: "Maps",
                        containerPath: "/tmp/Maps",
                        version: "",
                        icon: nil
                    ),
                    usage: LimitedCleanerUsage(
                        cacheBytes: 61_865_984,
                        temporaryBytes: 3_145_728,
                        removableItemCount: 92
                    )
                ),
                CleanerAppRecord(
                    app: InstalledApp(
                        bundleID: "com.apple.mobilesafari",
                        name: "Safari",
                        containerPath: "/tmp/Safari",
                        version: "",
                        icon: nil
                    ),
                    usage: LimitedCleanerUsage(
                        cacheBytes: 27_262_976,
                        temporaryBytes: 1_048_576,
                        removableItemCount: 48
                    )
                )
            ]
            records = samples
            selectedBundleIDs = Set(samples.map(\.id))
            scannedAppCount = 388
            isScanning = false
            return
        }
#endif
        let requestID = UUID()
        scanID = requestID
        isScanning = true
        scannedAppCount = 0
        selectedBundleIDs.removeAll()
        records.removeAll()

        DispatchQueue.global(qos: .userInitiated).async {
            var scannedBundleIDs = Set<String>()
            var discoveredRecords: [CleanerAppRecord] = []
            var processedCount = 0

            func publish(force: Bool = false) {
                guard force || processedCount.isMultiple(of: 8) else { return }
                let snapshot = discoveredRecords.sorted {
                    $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending
                }
                let count = processedCount
                DispatchQueue.main.async {
                    guard scanID == requestID else { return }
                    records = snapshot
                    scannedAppCount = count
                    if !snapshot.isEmpty {
                        selectedBundleIDs = Set(snapshot.map(\.id))
                    }
                }
            }

            func scanNewApps(_ applications: [InstalledApp]) {
                let metadata = Dictionary(
                    applications.map {
                        ($0.bundleID, $0)
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                let catalogApplications = applications.map {
                    CleanerResolvedApplication(
                        bundleID: $0.bundleID,
                        name: $0.name,
                        containerPath: $0.containerPath,
                        version: $0.version
                    )
                }
                let newRecords = CleanerCatalog.scanNewApplications(
                    catalogApplications,
                    scannedBundleIDs: &scannedBundleIDs,
                    shouldIncludeBundleID: {
                        ContainerPresentationPolicy.shouldShow(bundleID: $0)
                    },
                    activateContainer: { application in
                        var activationError: NSString?
                        return MCMActivateContainerPath(
                            2,
                            application.bundleID,
                            false,
                            &activationError
                        )
                    },
                    isValidContainerPath: ContainerStore.isApplicationContainerPath,
                    usageForContainer: { containerPath in
                        try? LimitedCleanerService.scan(
                            containerURL: URL(fileURLWithPath: containerPath, isDirectory: true),
                            rootValidator: { ContainerStore.isApplicationContainerPath($0.path) }
                        )
                    }
                )
                processedCount = scannedBundleIDs.count
                for record in newRecords {
                    let original = metadata[record.bundleID]
                    let resolvedApp = InstalledApp(
                        bundleID: record.bundleID,
                        name: record.application.name,
                        containerPath: record.containerPath,
                        version: record.application.version,
                        icon: original?.icon
                    )
                    discoveredRecords.append(
                        CleanerAppRecord(app: resolvedApp, usage: record.usage)
                    )
                }
                publish()
            }

            let apiApps = ContainerStore.installedAppsFromAPI()
            let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
            let mcmApps = ContainerStore.installedAppsFromMCM(identifiers: dynamicIdentifiers)
            scanNewApps(apiApps + mcmApps)

            let launchServicesIdentifiers = ContainerStore.launchServicesStoreIdentifiers()
            let candidates = MHAIdentifierCatalog.identifiers(
                dynamic: dynamicIdentifiers,
                installed: apiApps.map(\.bundleID),
                research: ContainerStore.researchAppIdentifiers,
                custom: [],
                launchServices: launchServicesIdentifiers
            )
            log("cleaner: resolving \(candidates.count) MHA-C2 bundle candidates")
            let mhaApps = ContainerStore.installedAppsFromMHACandidates(
                identifiers: candidates
            ) { progressiveApps in
                scanNewApps(progressiveApps)
            }
            scanNewApps(mhaApps)
            publish(force: true)

            DispatchQueue.main.async {
                guard scanID == requestID else { return }
                isScanning = false
                log(
                    "cleaner: scan complete bundles=\(processedCount) " +
                        "reclaimableApps=\(discoveredRecords.count)"
                )
            }
        }
    }

    private func beginClean() {
        guard !isBusy else { return }
        let selectedRecords = records.filter { selectedBundleIDs.contains($0.id) }
        guard !selectedRecords.isEmpty else { return }

        isCleaning = true
        freedBytes = 0
        removedItems = 0
        stalledItems = 0
        progress = 0
        stageLabel = language.text("cleaner.stage.preparing")
        showProgressCard = true
        if #available(iOS 16.1, *) {
            PatchActivityController.start(
                operation: language.text("cleaner.title"),
                detail: language.text("cleaner.available"),
                thermal: appState.thermalStateLabel
            )
        }

        progressTask?.cancel()
        progressTask = Task { @MainActor in
            // Floor only: measured progress from the purge loop leads this.
            while !Task.isCancelled && progress < 0.30 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if Task.isCancelled { return }
                progress = min(0.30, progress + 0.006)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var updatedUsage: [String: LimitedCleanerUsage] = [:]
            var freed: Int64 = 0
            var removed = 0
            var failed = 0
            var doneBytes: Int64 = 0
            let totalBytes = max(1, selectedRecords.reduce(Int64(0)) { $0 + max(1, $1.usage.totalBytes) })

            for (index, record) in selectedRecords.enumerated() {
                DispatchQueue.main.async {
                    stageLabel = record.app.displayName.uppercased()
                }

                guard let containerPath = ContainerStore.resolveAppContainerPath(
                    bundleID: record.app.bundleID
                ) else {
                    failed += 1
                    log("cleaner: bundle unavailable \(record.app.bundleID)")
                    continue
                }

                do {
                    let result = try LimitedCleanerService.clean(
                        containerURL: URL(fileURLWithPath: containerPath, isDirectory: true),
                        rootValidator: { ContainerStore.isApplicationContainerPath($0.path) }
                    )
                    updatedUsage[record.id] = result.after
                    freed += result.freedBytes
                    removed += result.removedItemCount
                    failed += result.failedItemCount
                    log(
                        "cleaner: cleaned \(record.app.bundleID) " +
                            "freed=\(result.freedBytes) removed=\(result.removedItemCount) " +
                            "failed=\(result.failedItemCount)"
                    )
                } catch {
                    failed += 1
                    log("cleaner: failed \(record.app.bundleID) error=\(error)")
                }

                doneBytes += max(1, record.usage.totalBytes)
                let measured = min(0.98, Double(doneBytes) / Double(totalBytes) * 0.98)
                DispatchQueue.main.async {
                    progress = max(progress, measured)
                }
            }

            DispatchQueue.main.async {
                progressTask?.cancel()
                progressTask = nil
                withAnimation(.easeOut(duration: 0.35)) {
                    progress = 1
                }
                records = records.compactMap { record in
                    guard let usage = updatedUsage[record.id] else { return record }
                    guard usage.totalBytes > 0 else { return nil }
                    return CleanerAppRecord(app: record.app, usage: usage)
                }
                selectedBundleIDs.removeAll()
                freedBytes = freed
                removedItems = removed
                stalledItems = failed
                isCleaning = false
                if #available(iOS 16.1, *) {
                    PatchActivityController.finish(detail: language.text("cleaner.scope_footer"))
                }
                log("cleaner: purge finished freed=\(freed) removed=\(removed) failed=\(failed)")
            }
        }
    }

    private func dismissProgress() {
        AppHaptics.tap()
        withAnimation(reduceMotion ? nil : AppMotion.surface) {
            showProgressCard = false
        }
        progress = 0
    }

    private func sizeText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

private struct CleanerAppRecord: Identifiable {
    let app: InstalledApp
    let usage: LimitedCleanerUsage

    var id: String { app.bundleID }
}
