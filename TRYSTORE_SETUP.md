# TryStore MAX build setup

The application target is **SupportPatch**, using the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included

- The signature-blue TryStore home screen, original character art, and social links.
- The classic **Loadout / Visuals** patch switcher. Tapping a module applies it; tapping the active module again restores its backup.
- Eight bundled `.TRYSTORE` packages, verified to target **Free Fire MAX** only: HEAD, NECK, HS PESSCOSO, HS SLA PECHO, BALAS, ARMAS, HOLOGRAMA EXCLUSIVO VERDE, and HOLOGRAMA EXCLUSIVO ROSADO. BALAS appears in AIM as **Balas Magicas**; ARMAS appears in Visuals as **Azul Exclusivo**. The retired HOLOGRAMA ARMAS and HOLOGRAMA PERSONAJE packages are removed. Existing `.3105` files remain supported for legacy imports.
- Airlift’s `DevicePatchService` integration for patch apply/restore operations.
- Bundled patch files are encrypted into named `.dataset` assets during CI; raw `.TRYSTORE` payloads are not copied into the IPA.

## Build on macOS or Codemagic

Install a stable Rust toolchain (`rustup` and `cargo`) on the macOS build machine. The unsigned build script rebuilds both Airlift iOS archives before Xcode links the app:

The CI workflow also requires `PATCH_BUNDLE_KEY_BASE64`, a protected CI secret containing the base64-encoded 32-byte asset encryption key. It regenerates the eight encrypted Data Sets before validation/build; do not put the key in source control or logs.

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./build_supportpatch_unsigned.sh
```

To build the XCFramework separately, or when your Codemagic workflow archives the Xcode project directly, run this before the Xcode build:

```bash
REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh
```

The rebuild script adds the required iOS Rust targets and recreates `AirliftFFI.xcframework`. Static symbol inspection is advisory for these LTO archives; Xcode's app link is the authoritative check for symbols used by the target. GitHub Actions installs stable Rust and uses the same unsigned build script.

See [BUILD_ON_MAC.md](BUILD_ON_MAC.md), [README.md](README.md), and [docs/PATCH_GUIDE.md](docs/PATCH_GUIDE.md) for additional build and patch details.
