# Design taste — TryStore interface doctrine

The interface is a dark instrument panel: near-black surfaces, one mint accent, monospaced
readings, and light that behaves like light. Everything below is already implemented in
`ThreeOneOSFive/views/DesignSystem.swift`; this file exists so new work extends the system
instead of inventing a parallel one.

## 1. Palette semantics

| Token | Role | Rule |
| --- | --- | --- |
| `canvas` | page | never used for a panel fill |
| `surface` | panel body | panels sit one step above canvas |
| `raised` | controls, chips | the only fill for small parts |
| `hairline` | empty rails, hairline edges | never for text |
| `textPrimary` | readings, headlines | ≥ 4.5:1 on canvas |
| `textSecondary` | labels | never below 11 pt |
| `textTertiary` | captions, meta | not for anything actionable |
| `mint` | the accent, active state, primary action | one per screen |
| `blue` | second data series only | never decoration |
| `amber` | in-progress, degraded, restore | never success |
| `coral` | failure only | never used decoratively |

State must never ride on colour alone: pair every tint with an icon, a label or a shape.

## 2. Type

- All sizes route through `UIFontMetrics` in `AppType`, so the interface follows
  Settings → Display & Brightness → Text Size. The root clamps the range to
  `.accessibility1` so 44 pt controls and gauge rings keep their geometry.
- `AppType.digits(_:)` is deliberately fixed and monospaced. Readings are data: a
  percentage, a byte count and a rule total must not reflow when the user enlarges text.
- Nothing below 11 pt. Labels are uppercase with 0.5–1.1 pt tracking; sentences are not.
- One idea per line. If a label needs two lines in a card, it is the wrong label.

## 3. Depth and light

- A panel is a material fill, a top-leading gradient, and a hairline edge that catches
  light — never a hard 1 px border alone.
- Depth comes from tone plus one soft shadow, not from stacking borders.
- `appSpecularSheen` is the signature effect: a wide 5.5 % white sweep that leans with the
  device. Budget: at most three lit surfaces per screen, and it never takes a touch.
- Depth is a stack, not a per-view value: `appDepthLayer(.backdrop | .hero | .card | .type)`
  with travel capped at 8 pt and rotation at 5 degrees. Never pass an ad-hoc intensity.
- Glass honours Reduce Transparency by falling back to an opaque fill. Blurred ambient
  lights and the blurred sweep are omitted under the same setting.

## 4. Motion

- Budgets: controls answer in 140 ms (`micro`), panels in 280 ms (`panel`); springs use
  `AppMotion.tile/surface/settle`, not ad-hoc curves.
- Screen entry is `appCinematicReveal` with staggered delays that stay under 0.4 s total.
  A slow reveal is a delay, not luxe.
- Anything that loops (shimmer, sheen, drift) stops under Reduce Motion. Progress must
  still read correctly when every animation is off.
- Progress bars report real work. A paced floor may cover the wait before the first
  measured step, and must never exceed it once real numbers arrive.

## 5. Layout

- 4 pt grid via `AppSpacing`; screen inset 20 pt.
- Radius ladder: `chip` 10, `control` 14, `tile` 18, `panel` 22, `hero` 28.
- Cards inside cards are a smell: use a divider or a raised chip instead.
- Horizontal density beats vertical length. Five modules fit in a 2-column grid where
  three rows used to be, which is why the patch deck is a deck and not a list.

## 6. Reuse, do not recreate

`AppSectionHeader`, `AppMetricTile`, `AppRingGauge`, `AppStatChip`, `AppActionButton`,
`AppIconBadge`, `AppHairline`, `AppEmptyState`, `AppSkeleton`/`AppSkeletonList`,
`AppPanelSurface` (`appPanel`). If a screen needs something new, build it in
`DesignSystem.swift` and use it in at least two places, or solve it with what exists.

## 7. HIG compliance checklist

- Dynamic Type, VoiceOver labels and traits, 44 pt targets, safe areas.
- Reduce Motion and Reduce Transparency honoured, including mid-session changes.
- Destructive or irreversible actions state their scope in the UI, in the user's language.
- The system tab bar stays the system tab bar: Liquid Glass, switch control and safe-area
  behaviour come free, and a custom bar forfeits all three.
- Every string exists in en, es, pt-BR, vi and zh-Hans.

## 8. Do not

New colours; a second accent; glow on text; emoji in the interface; more than one shadow
per surface; animation without a reduce-motion branch; hardcoded English; fixed-size text
where Dynamic Type is expected; spinners where a skeleton would show the shape of the
content; numbers that only exist to look busy.
