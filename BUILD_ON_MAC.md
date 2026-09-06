# JVZTXNX unsigned IPA build

## Current status

This project is a native SwiftUI iOS application. The source archive is intact, the Xcode project contains one `JVZTXNX` application target, and the included `build_unsigned.sh` script is configured to archive with code signing disabled and package the resulting `.app` inside an IPA payload.

A real iOS IPA cannot be compiled in this Linux environment because Apple’s Xcode toolchain, iOS SDK, and signing utilities are macOS-only. No fake or non-installable IPA has been generated.

## Build requirements

Use a Mac with:

- macOS and Xcode installed.
- The iOS platform components installed through Xcode.
- The project copied to a writable local folder.

The target declares iOS 16.0 as its minimum OS version and uses the bundle identifier `com.jvztxnx.cosmeticpreview`.

## Build commands

From the project root, run:

```bash
chmod +x ./build_unsigned.sh
./build_unsigned.sh
```

On success, the script creates:

```text
build/JVZTXNX.xcarchive
build/JVZTXNX-unsigned.ipa
```

The IPA is intentionally unsigned. An unsigned IPA is not directly installable on a normal iPhone or iPad; it must be signed with an Apple Developer certificate and a matching provisioning profile before installation. This unsigned package is also the intended input for an on-device signer such as eSign.

To validate the package layout before transferring it to the device, run:

```bash
chmod +x ./build_esign_ready_ipa.sh
./build_esign_ready_ipa.sh
```

The validator checks for one app bundle at `Payload/JVZTXNX.app`, the expected executable and `Info.plist`, and the absence of an existing code signature or embedded provisioning profile. eSign can then apply the owner’s `.p12` certificate and matching `.mobileprovision` profile. The profile must authorize `com.jvztxnx.cosmeticpreview`, or the signer must replace the bundle identifier with one authorized by the profile.

## Optional signed installation workflow

For a signed build, open `ThreeOneOSFive.xcodeproj` in Xcode, select the `JVZTXNX` target, choose the appropriate Apple Developer Team under **Signing & Capabilities**, and use a physical-device or generic-iOS destination. Alternatively, sign the archived app with the owner’s own certificate and provisioning profile using Apple’s supported distribution workflow.

## Project details verified

| Item | Value |
|---|---|
| Project | `ThreeOneOSFive.xcodeproj` |
| Scheme / target | `JVZTXNX` |
| App type | SwiftUI iOS application |
| Minimum iOS | 16.0 |
| Marketing version | 1.1.1 |
| Build number | 8 |
| Bundle identifier | `com.jvztxnx.cosmeticpreview` |
| App icon | `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| Bundled resource | `Resources/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D` |

The source ZIP passed archive-integrity testing. The build script was also hardened with a preflight message so it exits clearly when run without `xcodebuild`.
