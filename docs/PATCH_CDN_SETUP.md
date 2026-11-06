# TryStore patches — local IPA bundle

The iOS app does not check a remote patch feed, download patch packages, request a patch decryption key, or report patch-feed status. The approved `.TRYSTORE` packages under `ThreeOneOSFive/Patches/` are copied into the app bundle as the `Patches` folder. After license validation, the app imports those local files into its patch library; patch selection, activation, restore, and backups operate on the local package data.

## Update the bundled patch snapshot

1. Replace or add the approved `.TRYSTORE` source files under `ThreeOneOSFive/Patches/`.
2. Update the bundled package list in `ThreeOneOSFive/helpers/PatchProjectStore.swift` and the matching filename list in `ThreeOneOSFive/helpers/PatchResourceBundle.swift`.
3. Run `python3 scripts/verify_legacy_patch_bundle.py` and build a new IPA.
4. Install the new IPA. Existing installations do not receive patch changes remotely; a new IPA is required.

The build and app no longer need the `PATCH_BUNDLE_KEY_BASE64` CI secret or the Cloudflare `patch-bundle-key` endpoint for TryStore's bundled packages. The shared Cloudflare license-validation route remains a separate feature. Shared Worker code used by other projects is intentionally not removed by this app-side change.
