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

## Current patch resources

The bundled `.3105` packages are encrypted with AES-256-GCM and included in the IPA as:

```text
ThreeOneOSFive/Patches/Encrypted/*.3105.enc
```

At runtime the app validates the license, retrieves the 32-byte decryption key from the Cloudflare Worker, and decrypts each resource for import. The Worker secret is `PATCH_BUNDLE_ENCRYPTION_KEY`; it is not part of this repository or the app bundle. See [license activation](docs/LICENSE_ACTIVATION.md) for the endpoint and the re-encryption command. The plaintext `.3105` source files remain build inputs but are not listed in the Xcode Resources build phase.

The build script verifies the checked-in Airlift exports. For this merged checkout, rebuild it before archiving with `REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh`; this refreshes the framework when new Rust FFI functions are added.
