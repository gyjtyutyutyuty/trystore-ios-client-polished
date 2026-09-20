# 3105 TryStore build

This repository keeps the full **3105** application GUI and document workflow. It uses the original bundle identifier `com.apple.mobile.MobileHouseArrest`, preserves `.3105` document import/export, Files sharing, and the `threeoneosfive://` import URL, and applies TryStore branding through the in-app name, artwork, theme, and app icon.

## Compatibility and patch visibility

The full 3105 interface remains available, including the Patch and Files workflows, settings, cleaner, wallpaper tools, and compatibility diagnostics. The compatibility screen reports the detected iOS version/build, device identity, integrity state, and whether the protected device-level features are supported. Patch projects and bundled packages remain inspectable through the normal 3105 patch UI; unsupported package formats and incompatible device states are reported instead of being silently applied.

The requested TryStore packages are bundled in `ThreeOneOSFive/Patches/` and registered as application resources:

- `HOLOGRAMAARMAS.3105`
- `HSPESSCOSO.3105`
- `HS SLA PECHO.3105`

The source project also contains the other original 3105/TryStore bundled resources already present in the full GUI build.

## TryStore Cloudflare license API

The license manager uses the published TryStore Cloudflare validation endpoint:

`https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`

It sends the entered key, a device identifier, app version, and project ID `trystore`. The server response is interpreted using the existing `valid`, `outcome`, and `expiresAt` contract. The active license token and expiration are stored in the iOS Keychain with device-only accessibility. No Cloudflare administration credentials are embedded in the app.

A key must be active and issued for the `trystore` project. An invalid, expired, revoked, frozen, or wrong-project key is correctly rejected by the server and shown in the app as an inactive key state.

## Build

Codemagic uses the shared `3105` scheme and `build_unsigned.sh` to create `build/3105-unsigned.ipa`. The workflow validates the project, patch resources, Cloudflare configuration, and final IPA contents before publishing the IPA and archive as artifacts.
