# TryStore — Cosmetic Chest Preview

This revision turns the supplied 3105 project into a normal SwiftUI iOS app with a Files/document-picker workflow.

## Included

- Lion-themed `IMG_0022.jpeg` artwork as the visual theme.
- Lion artwork installed as the 1024×1024 app icon.
- Supplied `cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D` bundled as an app resource.
- Two user-owned profile labels:
  - `com.dts.freefiremax`
  - `com.dts.freefireth`
- `Aim Chest` cosmetic-only control.
- Document Picker folder access with security-scoped bookmarks.
- Relative-path validation rejecting empty components, `.`, `..`, `/`, and `\\`.
- Symlink rejection for the selected root and target path.
- Backup before replacement.
- Staged copy plus atomic rename.
- SHA-256 verification after replacement.
- Automatic rollback from the backup when replacement or verification fails.

## Asset path

The app resolves the requested relative asset path:

`Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D`

If Files exposes the `Documents` directory itself, the app uses it as the root and resolves the remaining components. If Files exposes the game container root, the app resolves the full path above.

## macOS + Xcode

1. Open `ThreeOneOSFive.xcodeproj` in Xcode.
2. Select the `TryStore` target.
3. In **Signing & Capabilities**, choose the owner's Apple Developer Team and keep automatic signing enabled.
4. Select a physical iPhone/iPad or a generic iOS device destination.
5. Build with **Product → Build**.
6. For a signed archive, use **Product → Archive** and export it from Organizer with the owner's signing identity.

### Unsigned archive / IPA

The repository includes `build_unsigned.sh`. On macOS with Xcode installed:

```bash
chmod +x ./build_unsigned.sh
./build_unsigned.sh
```

It creates:

- `build/TryStore.xcarchive`
- `build/TryStore-unsigned.ipa`

The IPA is intentionally unsigned. This is the correct input for a re-signing utility such as **eSign**: the selected Apple certificate (`.p12`) and matching provisioning profile (`.mobileprovision`) are applied by eSign for the target device and Apple Developer account.

To validate the package before importing it into eSign, run:

```bash
chmod +x ./build_esign_ready_ipa.sh
./build_esign_ready_ipa.sh
```

The validator confirms that the IPA contains exactly one `Payload/*.app`, has the expected executable and `Info.plist`, and does not already contain `_CodeSignature` or `embedded.mobileprovision`. Do not use an App Store-exported IPA as the input to this workflow.

### eSign installation workflow

1. Build `build/TryStore-unsigned.ipa` on macOS using the command above.
2. Transfer the IPA to the iPhone or iPad, then open it from the Files app or import it into eSign.
3. In eSign, import the owner’s `.p12` certificate and matching `.mobileprovision` profile. The profile must authorize the app’s bundle identifier, `com.trystore.cosmeticpreview`, or the identifier must be changed during signing to one authorized by that profile.
4. Sign the IPA without injecting additional tweaks or dynamic libraries, then install it from eSign.
5. Trust the developer profile in **Settings → General → VPN & Device Management** if iOS requests it. Installation still depends on a valid certificate, a matching profile, registered device UDID where applicable, and the iOS version supported by that certificate/profile.

The project intentionally declares no app groups, push notifications, keychain-sharing groups, extensions, background modes, or other special entitlements. Its standard Files/document-picker behavior therefore remains available after re-signing, subject to the normal iOS sandbox and profile rules.

## Scope of Aim Chest

`Aim Chest` only replaces the supplied cosmetic chest asset at the validated relative path. It contains no aiming logic, player targeting, recoil control, injection, jailbreak code, kernel code, sandbox escape, or third-party process modification.
