import SwiftUI

/// The body region a patch package actually writes to. Names come from the
/// shipped packages (`HEAD`, `NECK`, `HS SLA PECHO`, `Drag con Cuello`,
/// `Balas Magicas`), so resolution is by name rather than by tag.
enum PatchAimZone: String, CaseIterable, Identifiable {
    case head
    case neck
    case chest
    case aboveHead
    case fullBody
    case other

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .head: return "patch.zone.head"
        case .neck: return "patch.zone.neck"
        case .chest: return "patch.zone.chest"
        case .aboveHead: return "patch.zone.above_head"
        case .fullBody: return "patch.zone.full_body"
        case .other: return "patch.zone.other"
        }
    }

    var icon: String {
        switch self {
        case .head: return "scope"
        case .neck: return "person.fill"
        case .chest: return "lungs.fill"
        case .aboveHead: return "arrow.up.to.line"
        case .fullBody: return "circle.dashed"
        case .other: return "square.dashed"
        }
    }

    var isBodyZone: Bool { self != .other }

    /// Anchor in the stage square. The mesh is normalised to one unit tall and
    /// the camera keeps 0.76 units of half-height on screen, so a world Y maps
    /// to `0.5 - y * 0.6579` — these are the measured values for the shipped
    /// ROUK and SAKURA rigs.
    var anchor: UnitPoint {
        switch self {
        case .head: return UnitPoint(x: 0.5, y: 0.237)
        case .neck: return UnitPoint(x: 0.5, y: 0.289)
        case .chest: return UnitPoint(x: 0.5, y: 0.371)
        case .aboveHead: return UnitPoint(x: 0.5, y: 0.132)
        case .fullBody: return UnitPoint(x: 0.5, y: 0.5)
        case .other: return UnitPoint(x: 0.5, y: 0.5)
        }
    }

    /// Where the label floats. Kept off the silhouette so the mesh stays legible.
    var calloutCenter: UnitPoint {
        switch self {
        case .head: return UnitPoint(x: 0.225, y: 0.205)
        case .neck: return UnitPoint(x: 0.785, y: 0.325)
        case .chest: return UnitPoint(x: 0.215, y: 0.415)
        case .aboveHead: return UnitPoint(x: 0.5, y: 0.085)
        case .fullBody: return UnitPoint(x: 0.5, y: 0.885)
        case .other: return UnitPoint(x: 0.5, y: 0.885)
        }
    }

    static let calloutZones: [PatchAimZone] = [.head, .neck, .chest, .aboveHead, .fullBody]

    static func resolve(projectName: String) -> PatchAimZone {
        let key = projectName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }

        if key.contains("BALAS") || key.contains("MAGICAS") || key == "TRYSTORE" {
            return .fullBody
        }
        if key.contains("DRAG") {
            return .aboveHead
        }
        if key.contains("CUELLO") || key.contains("NECK") || key.contains("PESSCOSO") || key.contains("PESCUEZO") {
            return .neck
        }
        if key.contains("PECHO") || key.contains("CHEST") {
            return .chest
        }
        if key.contains("HEAD") || key.contains("CABEZA") {
            return .head
        }
        return .other
    }
}

/// The patch tab's body map: the same SceneKit character used by Home, turning
/// continuously under the HUD callouts.
struct PatchBodyStageView: View {
    let model: HeroCharacterModel
    let zone: PatchAimZone?
    var onSelect: ((PatchAimZone?) -> Void)? = nil

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.appPerformanceMode) private var performanceMode
    @Environment(\.appLanguage) private var language
    @State private var isVisible = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                backdrop
                CharacterStageView(
                    model: model,
                    reduceMotion: reduceMotion,
                    isActive: isVisible,
                    turntable: true
                )
                anchorMarkers(in: size)
                calloutLines(in: size)
                callouts(in: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            isVisible = true
            guard !reduceMotion, !performanceMode else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear { isVisible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text("patch.stage.accessibility"))
        .accessibilityValue(language.text((zone ?? .other).titleKey))
    }

    private var backdrop: some View {
        ZStack {
            AppPalette.canvas

            RadialGradient(
                colors: [AppPalette.brand.opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: 0.46),
                startRadius: 4,
                endRadius: 190
            )

            Circle()
                .strokeBorder(AppPalette.brand.opacity(0.22), lineWidth: 1)
                .frame(width: 250, height: 250)

            Circle()
                .strokeBorder(AppPalette.brand.opacity(0.10), lineWidth: 1)
                .frame(width: 302, height: 302)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func anchorMarkers(in size: CGSize) -> some View {
        if let zone, zone.isBodyZone {
            if zone == .fullBody {
                RoundedRectangle(cornerRadius: 96, style: .continuous)
                    .strokeBorder(
                        AppPalette.brand.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                    )
                    .frame(width: size.width * 0.46, height: size.height * 0.74)
                    .position(x: size.width * 0.5, y: size.height * 0.5)
                    .allowsHitTesting(false)
            } else {
                let point = CGPoint(x: zone.anchor.x * size.width, y: zone.anchor.y * size.height)
                ZStack {
                    Circle()
                        .stroke(AppPalette.brand.opacity(0.6), lineWidth: 1)
                        .frame(width: 30, height: 30)
                        .scaleEffect(pulse && !reduceMotion ? 1.35 : 0.85)
                        .opacity(pulse && !reduceMotion ? 0.15 : 0.75)
                    Circle()
                        .fill(AppPalette.brand)
                        .frame(width: 7, height: 7)
                        .shadow(color: AppPalette.brand.opacity(0.9), radius: 9)
                }
                .position(point)
                .allowsHitTesting(false)
            }
        }
    }

    private func calloutLines(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard let zone, zone.isBodyZone else { return }
            var path = Path()
            path.move(to: CGPoint(
                x: zone.calloutCenter.x * canvasSize.width,
                y: zone.calloutCenter.y * canvasSize.height
            ))
            path.addLine(to: CGPoint(
                x: zone.anchor.x * canvasSize.width,
                y: zone.anchor.y * canvasSize.height
            ))
            context.stroke(
                path,
                with: .color(AppPalette.brand.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func callouts(in size: CGSize) -> some View {
        ZStack {
            ForEach(PatchAimZone.calloutZones) { candidate in
                calloutItem(candidate)
                    .position(
                        x: candidate.calloutCenter.x * size.width,
                        y: candidate.calloutCenter.y * size.height
                    )
            }
        }
    }

    @ViewBuilder
    private func calloutItem(_ candidate: PatchAimZone) -> some View {
        if let onSelect {
            Button {
                AppHaptics.select()
                onSelect(zone == candidate ? nil : candidate)
            } label: {
                chip(candidate)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel(language.text(candidate.titleKey))
            .accessibilityAddTraits(zone == candidate ? AccessibilityTraits.isSelected : AccessibilityTraits())
        } else {
            chip(candidate)
        }
    }

    private func chip(_ candidate: PatchAimZone) -> some View {
        let active = zone == candidate
        let dimmed = zone != nil && !active

        return HStack(spacing: 5) {
            Image(systemName: candidate.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? AppPalette.brand : AppPalette.textTertiary)
            Text(language.text(candidate.titleKey))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(active ? AppPalette.textPrimary : AppPalette.textTertiary)
                .fixedSize()
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(active ? AppPalette.brand : AppPalette.textTertiary.opacity(0.55))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(active ? AppPalette.brand.opacity(0.18) : AppPalette.surface.opacity(0.9))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .strokeBorder(
                    active ? AppPalette.brand.opacity(0.95) : AppPalette.hairline.opacity(0.7),
                    lineWidth: 1
                )
        }
        .shadow(color: active ? AppPalette.brand.opacity(0.45) : .clear, radius: 10)
        .opacity(dimmed ? 0.5 : 1)
        .animation(.easeOut(duration: AppMotion.control), value: zone)
    }
}
