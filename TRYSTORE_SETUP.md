# TryStore MAX build setup

The application target is **SupportPatch**, using the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included

- The signature-blue TryStore home screen, original character art, and social links.
- The classic **Loadout / Visuals** patch switcher. Tapping a module applies it; tapping the active module again restores its backup.
- The patch catalog and UI mappings for authenticated remote delivery. Patch payload source files remain in the repository for feed maintenance and CI validation, but are not Xcode resources and must not be included in the app or IPA. All eleven feed patches are retrieved only after license/device authorization. Existing `.3105` files remain supported for legacy imports.
- Airlift’s `DevicePatchService` integration for patch apply/restore operations.

Downloaded feed packages are saved with iOS complete file protection. Their content keys are kept in the device-only Keychain rather than inside the cached package files; the app migrates trusted legacy feed caches to this format. This raises the bar against copying files from the app container, but cannot guarantee secrecy on a jailbroken or otherwise fully compromised device while the app is running.

The shared feed-wrapping key is no longer returned as plaintext: the app requests it with a POST and the Worker encrypts it to a P-256 public key supplied by the client using ECDH, HKDF-SHA256, and AES-GCM. The official app keeps the corresponding private key in Secure Enclave and the unwrapped shared key in memory only. The Worker does not attest that a submitted public key is actually Secure Enclave-backed; a licensed modified client can supply its own key, and a compromised live process can capture plaintext/key material. The legacy GET is intentionally rejected, so deploy the matching Worker code before distributing this app build.

The patch Worker can require the Ed25519 session returned by the license Worker on every TryStore manifest, bundle-key, report, and blob request. The session is short-lived and bound to the project and device ID; it prevents direct URL scraping, forged sessions, replay after expiry, and cross-device reuse. The production rollout order is: build and test this client, distribute the updated client, confirm all supported clients send `X-TryStore-Session`, then deploy the Worker with `REQUIRE_SIGNED_SESSION = "1"`. Enabling the gate before client rollout will intentionally reject older clients. This protects server authorization but does not make a valid licensed client on a user-controlled or jailbroken device unmodifiable; App Attest is the next stronger defense for modified IPA rejection.

## Build on macOS or Codemagic

Install a stable Rust toolchain (`rustup` and `cargo`) on the macOS build machine. The unsigned build script rebuilds both Airlift iOS archives before Xcode links the app:

Run `python3 scripts/verify_legacy_patch_bundle.py` before building to verify source package mappings and authenticated remote-delivery wiring. The build script also checks the archived app and final IPA to fail the build if any `.TRYSTORE`/`.3105` package or `Patches` directory is present.

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./build_supportpatch_unsigned.sh
```

To build the XCFramework separately, or when your Codemagic workflow archives the Xcode project directly, run this before the Xcode build:

```bash
REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh
```

The rebuild script adds the required iOS Rust targets and recreates `AirliftFFI.xcframework`. Static symbol inspection is advisory for these LTO archives; Xcode's app link is the authoritative check for symbols used by the target. GitHub Actions installs stable Rust and uses the same unsigned build script.

See [BUILD_ON_MAC.md](BUILD_ON_MAC.md), [README.md](README.md), and [docs/PATCH_GUIDE.md](docs/PATCH_GUIDE.md) for additional build and patch details.
