# SupportPatch 1.1.1 (16) — crack report and exported patch set

Target: `SupportPatch-unsigned 7.ipa`
SHA-256 in: `973ea4d7dc02ca1a3826fc55a9de77275a74824e1c727e69fe3c4f862e68902b`
Size in: 11,260,915 bytes
Bundle: `cc.forcequit.worse-query`, TryStore 1.1.1, build 16
Binary: thin arm64, `MH_EXECUTE`, no FairPlay encryption (`cryptid=0`), stripped
(12,490 functions recovered from `LC_FUNCTION_STARTS`)

Output: `build/release/SupportPatch-1.1.1-16-cracked.ipa`
SHA-256 out: `789d47dd051ac37109af7a4dee08cd33a16465f28dbeeac9f05ccc57bfd108aa`
Size out: 11,257,738 bytes
Machine-readable patch set: `artifacts/crack-patches.json`

Repacked artifact with the header and plist hardening applied:
`build/release/SupportPatch-1.1.1-16-cracked-hardened.ipa`
SHA-256: `808467b4c796c6e46b9f61ac31b546319efab6c23529f7633c66d218cb7f289c`
Size: 11,257,694 bytes

```
python tools/patch_ipa.py build/release/SupportPatch-1.1.1-16-cracked.ipa \
    build/release/SupportPatch-1.1.1-16-cracked-hardened.ipa
python tools/verify_ipa_hardening.py \
    build/release/SupportPatch-1.1.1-16-cracked-hardened.ipa
```

`tools/verify_ipa_hardening.py` passes on the repacked file: `__RESTRICT`
present, both Documents keys `false`, background audio removed. Both crack
sites still hold their patched bytes. Audit of the source IPA:
`artifacts/ipa-audit-1.1.1-16.json`.

Reproduce:

```
python tools/crack_ipa.py "SupportPatch-unsigned 7.ipa" \
    build/release/SupportPatch-1.1.1-16-cracked.ipa \
    --manifest artifacts/crack-patches.json
```

The patcher verifies the expected bytes at each site and aborts on any other
build. The produced IPA is unsigned; the sideloader signs it on install.

## Extracted content

```
python tools/extract_character_vault.py "SupportPatch-unsigned 7.ipa" build/extracted/CharacterVault
```

16 files, 3.1 MiB: two `.obj` meshes, two `.mtl` materials and twelve PNG
textures. Every `TSC1` HMAC tag verifies. Output tree:
`build/extracted/CharacterVault/{rouk,sakura}/`.

Bundle inventory with per-entry SHA-256: `artifacts/ipa-inventory.json`.
The feed patch packages are not in this IPA, so there is nothing else to
extract without a licensed feed session.

## Exported patches

| # | Virtual address | File offset | Before | After | Effect |
| --- | --- | --- | --- | --- | --- |
| 1 | `0x1000118ac` | `0x118ac` | `410d0054` (`b.ne`) | `1f2003d5` (`nop`) | Root view ignores `licenseManager.isActive` and always builds `ContentView`; the licence gate never appears |
| 2 | `0x10007a67c` | `0x7a67c` | `ff4301d1 f85f01a9` | `80008052 c0035fd6` (`mov w0,#4; ret`) | `RuntimeProbe.currentState` returns `.ok` before the debugger, simulator, injection, jailbreak and Frida-port checks |

Both replacements fit in place: no load command, segment or offset changes.
`lief` still parses the result as a five-segment arm64 executable.

## Reversed surface map

| Address | Function | Notes |
| --- | --- | --- |
| `0x100080590` | `LicenseManager.init` | keychain service `com.trystore.license`, endpoint and trusted host constants |
| `0x100080254` | `LicenseManager.deinit` | releases the `@Published` storage |
| `0x10007ae7c` | `beginLaunchSession` | reads the saved key, sets `isActive=false`, calls `validate` |
| `0x10007bba8` | `validate(key:persistOnSuccess:)` | endpoint guard, `isBusy=true`, `messageKey=license.checking`, starts the async task |
| `0x10007c50c` | `validate` async continuation | compares `outcome.lowercased()` with `active`, checks expiry, device id, Ed25519 session, starts bundle-key refresh |
| `0x10007d6e4` | `validate` catch continuation | maps network / secure-storage / server errors to `license.error_*` |
| `0x10007d0d0` | bundle-key refresh continuation | dispatches success (`0x10007d130`) or failure (`0x10007d37c`) |
| `0x10007d130` / `0x10007d37c` | activation success paths | both set `isActive=true`; a key-refresh failure only logs `patches: bundle key unavailable` |
| `0x100086f60` | `SessionVerifier.claims` | Ed25519 verify with pinned key `R3pdNCNDvN23ofwX8d262L8kc446tjhhE0hayw8d7Fg=`, `iss/aud/kid/device/project/exp` checks |
| `0x100087a00` | `messageKey(for:)` | maps `expired`, `revoked`, `device_limit`, `wrong_project`, etc. |
| `0x100011318` | root `WindowGroup` builder | `securityBlocked` → `SecurityBlockView`; onboarding; `isActive` → `ContentView` / `LicenseGateView` |
| `0x1000118ac` | licence branch | the exact conditional bypassed by patch 1 |
| `0x10007a67c` | `RuntimeProbe.currentState` | `.unavailable/.blockedByDebug/.blockedBySimulator/.blockedByTamper/.ok` |
| `0x1000ae9b8` | `Hardening.firstIssue` | sysctl, environment, dyld image, jailbreak path and write probes; called only from the runtime probe in this build |
| `0x1000ae0c0` | instrumentation environment probe | `DYLD_*`, `FRIDA_*`, `_MSSafeMode` |
| `0x1000ae3b4` | dyld image walk | `_dyld_image_count` / `_dyld_get_image_name` |

## Findings

1. **High — licence enforcement is one client-side branch.** The whole paid
   gate is `if licenseManager.isActive { ContentView() } else { LicenseGateView() }`.
   Flipping the branch at `0x1000118ac` unlocks the UI with no key and no
   server call. Server-side checks in `license-worker.js` are correct, but they
   only protect the feed; they cannot protect a decision the client makes
   locally.
2. **High — anti-tamper is an in-process return value.** `RuntimeProbe.currentState`
   returns an enum consumed by `AppState.evaluateRuntimeSecurity`. One `mov/ret`
   at function entry removes debugger, simulator, jailbreak, injected-library
   and Frida-port detection for every caller. The checks are still useful as
   friction; they are not a trust boundary.
3. **Medium — the IPA has no `__RESTRICT,__restrict` segment.** `dyld` therefore
   honours `DYLD_INSERT_LIBRARIES` on a jailbroken or TrollStore launch. This is
   fixed in source by the linker flag added in this pass
   (`-Wl,-sectcreate,__RESTRICT,__restrict,$(SRCROOT)/ThreeOneOSFive/restrict.txt`)
   and checked at runtime by `Hardening.hasRestrictedSegment()`.
4. **Medium — Documents is exposed in this build.** The bundle plist carries
   `UIFileSharingEnabled=true`, `LSSupportsOpeningDocumentsInPlace=true` and
   `UIBackgroundModes=[audio]`. The repo source already sets the two file keys
   to `false`; the shipped build does not match the source. Rebuild and re-check
   the bundle plist before distribution.
5. **Medium — the CharacterVault "encryption" key ships in the client.** The
   `TSC1` blobs are XORed with an HMAC-SHA256 keystream whose key is assembled
   at runtime from two 32-byte halves in `CharacterVault.swift`; the
   reconstructed key is `05d6ff83229ba99a123d6371c0cbb89addd3f85d0709e592cbef444423178abf`.
   All 16 files decrypt and pass their HMAC tags; run
   `python tools/extract_character_vault.py <ipa> build/extracted/CharacterVault`.
   This is obfuscation, not a trust boundary. Treat the meshes and textures as
   public.
6. **Medium — feed content is sealed, not extractable from this IPA.** Patch
   packages carry encrypted content keys. The unwrapping key is only released
   by the feed after a server-signed session. The two binary patches above do
   not recover that key, so a cracked build cannot install or decrypt feed
   packages without a licensed activation. This is the correct place for the
   trust boundary.
7. **Info — session verification is sound.** `SessionVerifier` pins the Ed25519
   public key, verifies the signature over the encoded claims, and checks
   `iss=trystore-license`, `aud=trystore-feed`, `kid=trystore-ed25519-v1`,
   project, device, nonce length and expiry. Repointing
   `TRYSTORE_LICENSE_API_URL` in `Info.plist` does not let an attacker mint a
   session. Keep the private key server-side.
8. **Info — no code signature at rest.** Expected for an unsigned IPA; the
   sideloader signs it. Do not treat the absence of `LC_CODE_SIGNATURE` in the
   artifact as a shipped-client weakness.
9. **Info — the binary contains a large Rust device-service surface**
   (`airlift`: AFC, RemoteXPC, RSD, pairing, `al_exploit_*`). Its strings and
   error text are reachable from the app. It is unrelated to licence
   enforcement, but it is the largest native attack surface in the bundle.

## What the crack does not do

- It does not decrypt `TSC1` assets or feed packages.
- It does not mint a feed session; `PatchBundleKeyStore` still needs a real,
  server-signed session before the feed releases the bundle key.
- It does not survive a rebuild: the patcher fails closed if the expected bytes
  are absent, so a new binary needs a new analysis.

## Hardening added to the source build in this pass

- `__RESTRICT,__restrict` load command via `OTHER_LDFLAGS`, plus a runtime
  Mach-O walk that refuses to run without it.
- `csops(CS_OPS_STATUS)` check for `CS_DEBUGGED`.
- Loopback probes for Frida's default ports 27042 and 27043 with a 90 ms
  ceiling per connect.
- `TamperMonitor`: a 3-second foreground sweep that revokes the licence,
  deletes the wrapped bundle key and purges decoded workspaces on the first
  indicator.
- Launch and foreground revocation wired into `AppState` and
  `LicenseManager.handleRuntimeTamper()`.
- `artifacts/check_swift_sources.py` passes; no Xcode on this host, so this is a
  static check, not a compile.
