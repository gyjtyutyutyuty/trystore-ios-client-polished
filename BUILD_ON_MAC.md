# SupportPatch unsigned IPA build

## Current status

This repository contains the merged SupportPatch SwiftUI app, its Airlift FFI framework, and the current `.bin` patch datasets under `ThreeOneOSFive/Assets.xcassets`. The old root-level TryStore GUI and legacy bundled `.3105` payloads are no longer part of the build.

A real iOS IPA cannot be compiled in this Linux environment because Apple’s Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated here.

## Build requirements

Use a Mac with:

- macOS and Xcode installed;
- iOS platform components installed through Xcode;
- Rust and the iOS Rust targets available for rebuilding Airlift;
- the project copied to a writable local folder.

## Build commands

From the project root, run:

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./ThreeOneOSFive/build-airlift-ffi.sh
./build_supportpatch_unsigned.sh
```

On success, the script creates:

```text
build/SupportPatch.xcarchive
build/SupportPatch-unsigned.ipa
```

The IPA is intentionally unsigned. It must be signed with an Apple Developer certificate and a matching provisioning profile before installation.

## Xcode target

Open `ThreeOneOSFive.xcodeproj`, choose the shared **SupportPatch** scheme, and build or archive for a physical iOS device. The target uses the bundle identifier declared in `ThreeOneOSFive/Info.plist`.

## Current patch resources

Patch payloads are asset-catalog datasets, not legacy `.3105` files. The current resources are in:

```text
ThreeOneOSFive/Assets.xcassets/**/*.dataset/*.bin
```

The `.3105` suffix remains only for the encrypted user patch-package import/export format handled by the patch workspace code.
