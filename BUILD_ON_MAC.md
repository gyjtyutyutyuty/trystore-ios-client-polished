# SupportPatch unsigned IPA build

## Current status

This repository contains the merged SupportPatch SwiftUI app, its Airlift FFI framework, image assets, and local `.TRYSTORE` patch packages. Xcode copies the `ThreeOneOSFive/Patches/` folder into the app bundle. A real iOS IPA cannot be compiled in this Linux environment because Apple’s Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated here.

## Build requirements

Use a Mac with:

- macOS and Xcode installed;
- iOS platform components installed through Xcode;
- Rust and the iOS Rust targets available if you intend to rebuild Airlift (Codemagic installs stable Rust automatically when it is missing);
- the project copied to a writable local folder.

## Build commands

From the project root, run:

```bash
chmod +x ./build_supportpatch_unsigned.sh
# Rebuilds Airlift, archives the app, and creates the unsigned IPA.
REBUILD_AIRLIFT=1 ./build_supportpatch_unsigned.sh
```

On success, the script creates:

```text
build/SupportPatch.xcarchive
build/SupportPatch-unsigned.ipa
```

The IPA is intentionally unsigned. It must be signed with an Apple Developer certificate and a matching provisioning profile before installation.

## Xcode target

Open `ThreeOneOSFive.xcodeproj`, choose the shared **SupportPatch** scheme, and build or archive for a physical iOS device. The target uses the bundle identifier declared in `ThreeOneOSFive/Info.plist`.

## Local patch packages
The approved `.TRYSTORE` files under `ThreeOneOSFive/Patches/` are copied as a folder resource into the IPA. At runtime, the app reads these local files and installs them into its local patch library. No patch decryption key, Cloudflare patch-key request, or patch-encryption CI secret is required. The packages are part of the IPA and are not hidden from someone who extracts it.

```text
ThreeOneOSFive/Patches/<PATCH_NAME>.TRYSTORE
```

The separate license check still calls the configured Cloudflare validation endpoint; removing the patch-key request does not remove the license gate. See [license activation](docs/LICENSE_ACTIVATION.md) for details.

**Important:** the checked-in XCFramework archives do not contain the `al_exploit_read_file` export required by the Swift remote-backup wrapper. The default framework check rejects these stale archives. Always build with `REBUILD_AIRLIFT=1` as shown above; Codemagic must do the same before archiving.
