# TryStore MAX build setup

The application target is **SupportPatch**, using the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included

- The signature-blue TryStore home screen, original character art, and social links.
- The classic **Loadout / Visuals** patch switcher. Tapping a module applies it; tapping the active module again restores its backup.
- Eight `.3105` patch packages, all verified to target **Free Fire MAX** only: HEAD, NECK, HS PESSCOSO, HS SLA PECHO, HOLOGRAMA ARMAS, HOLOGRAMA PERSONAJE, HOLOGRAMA EXCLUSIVO VERDE, and HOLOGRAMA EXCLUSIVO ROSADO.
- Airlift’s `DevicePatchService` integration for patch apply/restore operations.
- No regular Free Fire catalog or separate newer patch catalog; the eight bundled `.3105` packages are encrypted as asset-catalog Data Sets for app delivery.

## Build on macOS or Codemagic

Install a stable Rust toolchain (`rustup` and `cargo`) on the macOS build machine. The unsigned build script rebuilds both Airlift iOS archives before Xcode links the app:

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./build_supportpatch_unsigned.sh
```

To build the XCFramework separately, or when your Codemagic workflow archives the Xcode project directly, run this before the Xcode build:

```bash
REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh
```

The rebuild script adds the required iOS Rust targets and recreates `AirliftFFI.xcframework`. Static symbol inspection is advisory for these LTO archives; Xcode's app link is the authoritative check for symbols used by the target. GitHub Actions installs stable Rust and uses the same unsigned build script.

Before asset validation, both CI workflows regenerate all eight encrypted patch Data Sets from the source packages. Configure the protected Codemagic environment variable `PATCH_BUNDLE_ENCRYPTION_KEY` and the GitHub Actions secret `PATCH_BUNDLE_ENCRYPTION_KEY` with the same base64-encoded 32-byte key used by the Cloudflare Worker runtime secret. Builds fail fast if a key is missing or invalid; generation reads each Data Set back, verifies an AES-GCM round trip, and confirms that a one-bit-different key is rejected. Never commit or print the key.

See [BUILD_ON_MAC.md](BUILD_ON_MAC.md), [README.md](README.md), and [docs/PATCH_GUIDE.md](docs/PATCH_GUIDE.md) for additional build and patch details.
