# eSign Setup

This project is packaged as an **unsigned iOS IPA** so that the owner can apply their own Apple certificate and provisioning profile in an on-device signer such as eSign. The project has one application target, no extensions, and no declared special entitlements. The bundle identifier is `com.jvztxnx.cosmeticpreview`.

## Required inputs

Use an Apple signing certificate exported as a `.p12` file and a matching provisioning profile exported as a `.mobileprovision` file. The profile must authorize the bundle identifier, or the signer must replace the identifier with one authorized by the profile. Apple describes provisioning profiles as the mechanism used to authorize apps for particular devices and services [1]. Apple also documents that entitlements are embedded in the code signature and must be authorized by the profile [2].

The eSign project documentation describes importing a `.p12` certificate and `.mobileprovision` profile before signing an IPA [3]. Use certificates and profiles obtained from the owner’s Apple Developer account or another source the owner is authorized to use. Do not rely on public certificates of unknown provenance.

## Build and validate

Run these commands on a Mac with Xcode installed:

```bash
chmod +x ./build_unsigned.sh ./build_esign_ready_ipa.sh
./build_unsigned.sh
./build_esign_ready_ipa.sh
```

The second command verifies that the package has the expected `Payload/JVZTXNX.app` layout and has not already been signed. This environment cannot compile a real iOS IPA because Xcode, the iOS SDK, and Apple signing utilities are macOS-only; the validator therefore checks packaging structure only.

## Sign and install

Transfer `build/JVZTXNX-unsigned.ipa` to the device, import it into eSign, import the certificate and provisioning profile, and sign the IPA without injecting additional dynamic libraries. Install the signed output from eSign. If iOS prompts for trust, use **Settings → General → VPN & Device Management**.

Successful installation is not guaranteed by the source package alone. It depends on a valid certificate, a matching provisioning profile, device authorization where applicable, certificate status, and the iOS version supported by the signing material.

## References

[1]: https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices "Apple Developer: Distributing your app to registered devices"

[2]: https://developer.apple.com/documentation/bundleresources/entitlements "Apple Developer: Entitlements"

[3]: https://github.com/iOS17/Esign "GitHub: iOS17/Esign"
