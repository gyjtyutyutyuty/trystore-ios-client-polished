# eSign Setup

This project is packaged as an **unsigned iOS IPA** so that the owner can apply their own Apple certificate and provisioning profile in an on-device signer such as eSign. The project has one application target and no extensions. The bundle identifier is `cc.forcequit.worse-query` and the App Group it declares is `group.cc.forcequit.worse-query`.

## The App Group is not optional

On iOS 27.0–27.3 the patch feature runs on worse_query, and worse_query asks containermanagerd for a sandbox extension through the app's **App Group container**. Without a group in the signature there is no container to swap and the escape cannot start. The app then reports `patch.error.app_group_missing`; a group that is present but cannot be probed reports `patch.error.worse_query_unavailable` instead.

At runtime `worse_query_app_group()` reads `com.apple.security.application-groups` from the running process with `SecTaskCreateFromSelf` and uses the first group whose container resolves. It does **not** hardcode a group name, so any group the signature actually grants is enough — it does not have to be the one in `ThreeOneOSFive.entitlements`.

What the signer must supply:

- a certificate (`.p12`) and its password,
- a provisioning profile for an **explicit** App ID — a wildcard profile (`*`) cannot carry an App Group,
- that App ID must have App Groups enabled and at least one group assigned,
- the profile must be generated **after** the group was assigned, otherwise it still ships without it.

Free Apple IDs cannot register App Groups, so a paid developer account is required for this route. Tools that substitute the bundle identifier to match a foreign profile can still install, but the identifier then no longer matches the group's App ID and the container will not resolve.

## Required inputs

Use an Apple signing certificate exported as a `.p12` file and a matching provisioning profile exported as a `.mobileprovision` file. The profile must authorize the bundle identifier, or the signer must replace the identifier with one authorized by the profile. Apple describes provisioning profiles as the mechanism used to authorize apps for particular devices and services [1]. Apple also documents that entitlements are embedded in the code signature and must be authorized by the profile [2].

The eSign project documentation describes importing a `.p12` certificate and `.mobileprovision` profile before signing an IPA [3]. Use certificates and profiles obtained from the owner’s Apple Developer account or another source the owner is authorized to use. Do not rely on public certificates of unknown provenance, and do not sign under another developer’s App ID.

## Verify the signature before blaming the app

On a Mac, unzip the signed IPA and run:

```bash
codesign -d --entitlements :- Payload/TryStore.app
```

The output must contain `com.apple.security.application-groups`. If that key is absent, the profile dropped it and no amount of re-signing with the same profile will make worse_query run. The app logs the same conclusion:

```
patch: worse_query blocked — no App Group entitlement in the signed profile
```

## Build and validate

Run these commands on a Mac with Xcode installed:

```bash
chmod +x ./build_unsigned.sh ./build_esign_ready_ipa.sh
./build_unsigned.sh
./build_esign_ready_ipa.sh
```

The second command verifies that the package has the expected `Payload/SupportPatch.app` layout and has not already been signed. This environment cannot compile a real iOS IPA because Xcode, the iOS SDK, and Apple signing utilities are macOS-only; the validator therefore checks packaging structure only.

## Sign and install

Transfer the unsigned IPA to the device, import it into eSign, import the certificate and provisioning profile, and sign the IPA without injecting additional dynamic libraries. Install the signed output from eSign. If iOS prompts for trust, use **Settings → General → VPN & Device Management**.

Successful installation is not guaranteed by the source package alone. It depends on a valid certificate, a matching provisioning profile, device authorization where applicable, certificate status, and the iOS version supported by the signing material.

## References

[1]: https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices "Apple Developer: Distributing your app to registered devices"

[2]: https://developer.apple.com/documentation/bundleresources/entitlements "Apple Developer: Entitlements"

[3]: https://github.com/iOS17/Esign "GitHub: iOS17/Esign"

## Related documentation

See the [documentation index](DOCUMENTATION_INDEX.md), [TryStore setup](../TRYSTORE_SETUP.md), and [patch workspace guide](PATCH_GUIDE.md).
