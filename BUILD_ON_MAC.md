# SupportPatch unsigned IPA build

## Current status

This repository contains the SupportPatch SwiftUI app, its Airlift FFI framework, image assets, and reviewed TryStore patch source packages. The Xcode target deliberately does not add `ThreeOneOSFive/Patches/` to the app resources; patches are fetched from the authenticated Cloudflare feed after the app's license gate succeeds. A real iOS IPA cannot be compiled in this Linux environment because Apple's Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated here.

## Build requirements

Use a Mac with macOS and Xcode, iOS platform components installed through Xcode, and a writable copy of the project. Rust and the iOS Rust targets are needed if rebuilding Airlift (Codemagic installs stable Rust automatically when it is missing).

## Build commands

From the project root, run:

```bash
chmod +x ./build_supportpatch_unsigned.sh
# Rebuilds Airlift, archives the app, verifies patch assets are absent, and creates the unsigned IPA.
REBUILD_AIRLIFT=1 ./build_supportpatch_unsigned.sh
```

On success, the script creates `build/SupportPatch.xcarchive` and `build/SupportPatch-unsigned.ipa`. The IPA is intentionally unsigned. Sign it with an Apple Developer certificate and a matching provisioning profile before installation. The build script runs the patch verifier on the archived app; the verifier fails if a `.TRYSTORE`/`.3105` package or a `Patches` directory is present in the app bundle. Codemagic runs the same checks after packaging the IPA.

## Remote patches

The approved source packages remain in `ThreeOneOSFive/Patches/` for review and publishing, but they are not Xcode resources and must not be copied into the IPA. After a successful license check, the app fetches the TryStore manifest and packages over HTTPS. It verifies the server host, package size and SHA-256, then checks the canonical package UUID and identity before installation. The Cloudflare Worker must be deployed with the license check enabled before distributing this client build; use the rollout checklist in [PATCH_CDN_SETUP.md](docs/PATCH_CDN_SETUP.md). The live feed currently contains the app's 11 expected catalog packages.

A first successful patch sync requires internet access. The validated package is then cached in protected app storage, and ongoing license checks gate the app. This raises the cost of unauthorized distribution but cannot prevent an authorized device owner from extracting a package after download.

## Xcode target and framework

Open `ThreeOneOSFive.xcodeproj`, choose the shared **SupportPatch** scheme, and build or archive for a physical iOS device. The target uses the bundle identifier declared in `ThreeOneOSFive/Info.plist`. The checked-in XCFramework archives may lack the `al_exploit_read_file` export required by the Swift remote-backup wrapper, so keep `REBUILD_AIRLIFT=1` (the default) for archives; Codemagic must also rebuild Airlift before archiving.
