# TryStore MAX build setup

The application target is **SupportPatch**, using the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included

- The signature-blue TryStore home screen, original character art, and social links.
- The classic **Loadout / Visuals** patch switcher. Tapping a module applies it; tapping the active module again restores its backup.
- Seven historical `.3105` patch packages, all verified to target **Free Fire MAX** only: HEAD, NECK, HS PESSCOSO, HS SLA PECHO, Silent Aim, HOLOGRAMA ARMAS, and HOLOGRAMA PERSONAJE.
- Airlift’s `DevicePatchService` integration for patch apply/restore operations.
- No regular Free Fire catalog or newer `.dataset` patch catalog.

## Build on macOS or Codemagic

Install a stable Rust toolchain (`rustup` and `cargo`) on the macOS build machine. The unsigned build script rebuilds and validates both Airlift iOS archives before Xcode links the app:

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./build_supportpatch_unsigned.sh
```

To build the XCFramework separately, or when your Codemagic workflow archives the Xcode project directly, run this before the Xcode build:

```bash
REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh
```

The rebuild script adds the required iOS Rust targets, checks that the FFI exports match the headers, and recreates `AirliftFFI.xcframework`. GitHub Actions installs stable Rust and uses the same unsigned build script.

See [BUILD_ON_MAC.md](BUILD_ON_MAC.md), [README.md](README.md), and [docs/PATCH_GUIDE.md](docs/PATCH_GUIDE.md) for additional build and patch details.
