# SupportPatch unsigned IPA build

## Current status

This repository contains the merged SupportPatch SwiftUI app, its Airlift FFI framework, image assets, and encrypted bundled patch resources. A real iOS IPA cannot be compiled in this Linux environment because Apple’s Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated here.

## Build requirements

Use a Mac with:

- macOS and Xcode installed;
- iOS platform components installed through Xcode;
- Rust and the iOS Rust targets available if you intend to rebuild Airlift (Codemagic installs stable Rust automatically when it is missing);
- the project copied to a writable local folder.

## Build commands

From the project root, run:

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
# Rebuilds Airlift so all current Rust FFI exports are linked.
REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh
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

## Bundled patch payloads
The seven bundled `.3105` packages are combined into one AES-256-GCM archive and stored as base64 ciphertext in generated Swift source:

```text
ThreeOneOSFive/helpers/GeneratedPatchBundle.swift
```

The generated source is compiled into the app; none of the seven patch files or names are separate IPA resources. At runtime the app validates the license, retrieves the 32-byte decryption key from the Cloudflare Worker, decrypts the archive in memory, and imports its entries. The Worker secret is `PATCH_BUNDLE_ENCRYPTION_KEY`. See [license activation](docs/LICENSE_ACTIVATION.md) for key handling and the regeneration command. This hides the separate files from archive listings, but the ciphertext still resides in the executable and can be extracted by reverse engineering.

The build script verifies the checked-in Airlift exports. For this merged checkout, rebuild it before archiving with `REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh`; this refreshes the framework when new Rust FFI functions are added.
