# License-gated access mode

After onboarding, the app shows the license activation screen until the Cloudflare validation endpoint confirms an active TryStore key. A saved key is rechecked when the app starts or returns to the foreground; if the service cannot be reached, the console stays locked and the user can retry. Settings shows the license status and expiration, allows revalidation, and can remove the saved key.

The app saves a key only after successful validation, in the iPhone's device-only Keychain. The Cloudflare admin token and signing secret remain on the Worker and are not included in the app. See [the license activation integration guide](docs/LICENSE_ACTIVATION.md) for the endpoint contract and the current device-binding limitation.

## Build note

Build the iOS app on macOS with Xcode, or use the configured Codemagic workflow. See [Build on Mac](BUILD_ON_MAC.md) for the current build commands; no IPA can be compiled in the Linux sandbox.
