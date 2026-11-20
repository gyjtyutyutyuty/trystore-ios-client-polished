# Changelog

All notable user-facing changes are documented in this file.

## [Unreleased]
### Security
- Patch packages no longer carry a usable content key. The feed wraps each key under an app bundle key that is released only after licence and device validation, and the client stores it in the keychain for this device.
- Release builds now refuse a debugger, jailbreak filesystem, writable system paths, instrumentation variables, and dylibs injected outside the app bundle.
- Decoded patch workspaces moved out of `Documents`, where the Files app and Filza could read them, into application support with complete file protection, excluded from backups. A one-time migration moves and deletes the old `Documents/Patches` tree, and a hardening failure purges every workspace along with the licence.
- Bundle keys are now versioned end to end. The feed records the served version in `feed_key_state`, `/bundle-key` returns it with the matching secret, and `/rotate <project> <1|2>` re-wraps every stored package before switching over. Retiring a leaked key no longer needs an app build, and a missing secret fails closed instead of serving the previous key.
- The licence service enforces device binding by default, so one key cannot be validated from an unlimited number of devices; set `ENFORCE_DEVICE_BINDING=0` only to opt out deliberately.
- Every Worker webhook now compares its secret in constant time and rejects all calls when the secret is unset, key responses no longer carry a wildcard CORS header, the panel proxy only serves its configured path prefix, and the patch report endpoint rejects anything that is not JSON.

### Added
- iOS 26.0–26.6.1 now activates through `bad_query`, and iOS 26.7–26.7.2, 27.0–27.2, and the 27.3 beta 1 build `24C5037i` through `worse_query`. iOS 17.0–17.7.x and 18.0–18.7.1 keep the kernel chain; 18.7.2 and later stay on the pairing tunnel.
- Container identity on iOS 27.2 falls back to the worse_query identifier map when the metadata plist is no longer readable.
- The Home hero now renders the supplied character meshes and offers a ROUK / SAKURA picker.

### Fixed
- The SceneKit hero compiles against the current SDK, uses the real mesh bounds, and no longer intercepts vertical scrolling.
- Aim packages can no longer apply an Antena payload. Each shipped package carries a canonical payload fingerprint that is checked before activation, the feed rewrites a mismatched package instead of keeping it, and the Telegram publisher rejects an upload whose project name does not match the slot.
- A failed remote patch sync no longer stops the remaining packages; the library reports the missing entries instead of silently keeping stale bytes.

### Removed
- In-app patch package import and export are gone. The library is filled by the bundled `.TRYSTORE` resources and the authenticated feed sync only: the library toolbar button now just creates a project, and the app no longer registers for `.3105`/`TRYSTORE` documents or the `threeoneosfive://` scheme. Packages already installed in `Documents/Patches` keep working.
- The staging, routing, and share-sheet code behind those flows was deleted along with four localisation keys that no longer had a call site.

### Documentation
- Added the compatible patch-workspace guide from the supplied archive in English and Vietnamese.
- Added the archive’s 1.0.1 release notes under `docs/releases/`.
- Clarified that TryStore’s existing GUI, cosmetic-preview controls, document picker, backup, atomic replacement, verification, and rollback workflow remain unchanged.
- Reconciled the English/Vietnamese project documentation, setup notes, eSign guide, attribution notices, and documentation index.


## [1.0.1] - 2026-08-15

### Added

- Bundle-tree Patch workspace v2 under `On My iPhone/3105/Patches`, synchronized automatically when applying or exporting.
- Multiple independent Files tabs with preserved navigation state.
- ZIP extraction with path, symbolic-link, CRC, and available-space validation.
- Responsive iPad split-view and landscape navigation.
- Home toggles for showing or hiding Cleaner and Wallpaper features.

### Changed

- Patch creation from an app-container file or folder now captures the stable bundle identifier and editable destination tree automatically.
- Patch package imports no longer use the previous fixed payload-size or file-count ceiling; practical device storage and memory still apply.
- Files and Patch screens now use consistent grouped cards, compact icons, balanced nested rows, and stable search presentation.
- Legacy v1 `.3105` packages remain importable and usable.

### Fixed

- Patch Restore now restores files that existed before Apply, removes files introduced by the patch, and removes patch-created folders after they become empty.
- File navigation remains at the current folder when switching app sections and restores the correct folder independently for each Files tab.
- Empty Patch and Cleaner actions now share the same visual treatment.
- Corrected PosterBoard wallpaper activation guidance and the iOS 27 Collections prerequisite.
- Refined navigation icon rendering and nested file-row spacing.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 Developer Beta 1–4, including Public Beta 1–2 mappings listed in the app.
- Added iPhone and iPad interface support; device-level features still require enterprise signing.

## [1.0 beta 3] - 2026-08-14

### Added

- Bundle-based App Data Browser with MHA-C2 container discovery.
- Native file operations: search, multi-file import, rename, delete, create file/folder, and conflict handling.
- Portable `.3105` patch projects with optional password protection and file/folder rules.
- Limited per-app cleaner for `Library/Caches` and `tmp`.
- Wallpaper Lab for validated `.tendies` packages with installation receipts and targeted reset.
- English, Vietnamese, and Simplified Chinese localization.

### Changed

- Simplified the app into a five-tab, native SwiftUI layout inspired by focused iOS container tools.
- Moved the enterprise-signing notice below device information on Home.
- Refined the orange accent, empty states, actions, and navigation presentation.

### Fixed

- Stabilized persistent search presentation in app and file browsers.
- Fixed native document selection for replacement files and `.3105` package imports.
- Resolved bundle-name mapping for enumerated app containers where metadata is available.
- Limited wallpaper reset to active content installed by 3105.
- Corrected Cleaner layout when no removable app data is found.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 beta 1–4 builds listed in the app.
- Unlisted iOS 27 builds remain disabled until explicitly verified.
