# SupportPatch unsigned IPA build

## Current status

This repository contains the merged SupportPatch SwiftUI app, its Airlift FFI framework, image assets, and eight AES-GCM-encrypted patch Data Sets. Xcode compiles the `.bin` assets into `Assets.car`. A real iOS IPA cannot be compiled in this Linux environment because Apple’s Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated here.

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

## Encrypted patch assets
The eight remaining source `.3105` packages are encrypted individually with AES-256-GCM into `.bin` Data Sets named after their patches under `ThreeOneOSFive/Assets.xcassets/`. Xcode compiles those Data Sets into the single `Assets.car` archive, so ordinary IPA extraction does not show eight loose patch files. The encrypted payloads are still part of the IPA and could be recovered from `Assets.car` with asset-catalog tooling. Silent Aim has been removed from the source packages, asset catalog, and patch UI.

```text
ThreeOneOSFive/Assets.xcassets/<PATCH_NAME>.dataset/<PATCH_NAME>.bin
```

At runtime the app validates the license, retrieves the 32-byte key from `POST /api/v1/keys/patch-bundle-key`, reads the Data Sets through `NSDataAsset`, decrypts the packages in memory, and imports them. The key remains a Cloudflare Worker secret (`PATCH_BUNDLE_ENCRYPTION_KEY`); the Worker does not serve the patch ciphertext. To regenerate the encrypted assets after changing source packages, set `PATCH_BUNDLE_KEY_BASE64` in a private environment and run `node scripts/encrypt_bundled_patches.mjs`. See [license activation](docs/LICENSE_ACTIVATION.md) for the security boundary.

**Important:** the checked-in XCFramework archives do not contain the `al_exploit_read_file` export required by the Swift remote-backup wrapper. The default framework check rejects these stale archives. Always build with `REBUILD_AIRLIFT=1` as shown above; Codemagic must do the same before archiving.
