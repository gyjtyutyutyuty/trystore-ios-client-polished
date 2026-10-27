# TryStore (ThreeOneOSFive) — working notes for agents

iOS client: SwiftUI, iOS 16.1 deployment target (ActivityKit guarded at 16.1), five
shipped languages (en, es, pt-BR, vi, zh-Hans). Patch packages are applied through a
transaction that writes backups, journals its intent, then verifies every written file by
digest and rolls back on mismatch. `cloudflare/` holds the licence-activation and Telegram
Workers.

## Build and verification

Xcode is required to build. There is no Xcode in a cloud runner, so **never claim a build
or a compile you did not run** — report static checks as static checks.

Run these before every commit that touches Swift:

- Delimiter balance per edited file, with string literals and comments stripped first.
- Top-level type redeclaration scan, matching column-0 declarations only. Nested
  `CodingKeys`, `Entry` and `Coordinator` types repeat legitimately across files and are
  not duplicates.
- `Localizable.strings` validation across all five languages: no duplicate keys, no
  malformed lines, every new key present in every file.
- Memberwise-init drift: when a struct gains a field, re-check every call site. This is
  how the `LiveActivityState.ContentState` mismatch (declaration without `progress` and
  `operation`, while the controller and widget already passed them) was caught before it
  reached a build.

Signing and archiving happen on the maintainer's Mac — see `BUILD_ON_MAC.md`,
`build_supportpatch_unsigned.sh` and `codemagic.yaml`.

## Project conventions

- Never hardcode user-facing English in a view. Add the key to all five `.lproj` files.
- Colours, type, spacing, radii and motion come from `views/DesignSystem.swift` only.
  No new hex values, no one-off shadows, no second accent.
- Accessibility is part of done: Dynamic Type via `AppType`, VoiceOver labels and traits
  on every control, Reduce Motion and Reduce Transparency branches for anything that moves
  or blurs, 44 pt minimum hit targets.
- Device-only capability stays behind the support policy checks. Never assume a
  non-jailbroken device can read another app's container: on such a device the cleaner
  legitimately shows an empty state, and inventing numbers there is a bug.
- One concern per commit; the message says why, not what.

## Design doctrine

Read `docs/DESIGN_TASTE.md` before changing the interface. Short version: one accent,
depth from tone rather than borders, motion that answers the hand, and nothing decorative
without a reduce-motion path.
