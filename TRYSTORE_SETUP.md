# TryStore MAX build setup

The application target is **SupportPatch**, using the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included

- The signature-blue TryStore home screen, original character art, and social links.
- The classic **Loadout / Visuals** patch switcher. Tapping a module applies it; tapping the active module again restores its backup.
- Eight bundled `.TRYSTORE` packages, verified to target **Free Fire MAX** only: HEAD, NECK, HS PESSCOSO, HS SLA PECHO, BALAS, ARMAS, HOLOGRAMA EXCLUSIVO VERDE, and HOLOGRAMA EXCLUSIVO ROSADO. BALAS appears in AIM as **Balas Magicas**; ARMAS appears in Visuals as **Azul Exclusivo**. The retired HOLOGRAMA ARMAS and HOLOGRAMA PERSONAJE packages are removed. Existing `.3105` files remain supported for legacy imports.
- Airlift’s `DevicePatchService` integration for patch apply/restore operations.
- Bundled `.TRYSTORE` files are copied locally into the IPA under the `Patches` folder; no Cloudflare patch-key service or patch-encryption secret is needed.

## Build on macOS or Codemagic

Install a stable Rust toolchain (`rustup` and `cargo`) on the macOS build machine. The unsigned build script rebuilds both Airlift iOS archives before Xcode links the app:

Run `python3 scripts/verify_legacy_patch_bundle.py` before building to verify that each local package is present and mapped into the app catalog.

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
