# TryStore documentation index

This index covers the documentation reviewed from the supplied archive and the existing TryStore repository. TryStore keeps its current GUI and document workflow; archive material that would enable exploit, injection, anti-detection, or game-cheat behavior is intentionally not imported or activated.

## User and project documentation

| Document | Purpose |
| --- | --- |
| [README](../README.md) | Project scope, cosmetic-only workflow, asset path, build, signing, and safety boundaries. |
| [README tiếng Việt](../README.vi.md) | Vietnamese project overview and workflow summary. |
| [TryStore setup](../TRYSTORE_SETUP.md) | GUI/workflow preservation, bundled resources, compatibility notes, and build pipeline. |
| [Build on Mac](../BUILD_ON_MAC.md) | macOS/Xcode build requirements and unsigned IPA packaging. |
| [License-gated access](../NO_KEY_MODE.md) | Current licensing and protected-action behavior. |
| [License activation integration](LICENSE_ACTIVATION.md) | Cloudflare validation contract, Keychain behavior, and device-binding limitation. |
| [1.0.1 release notes](../1.0.1.md) | Root release note and quick patch workflow. |
| [Changelog](../CHANGELOG.md) | User-facing changes and documentation updates. |
| [Third-party notices](../THIRD_PARTY_NOTICES.md) | Attribution and license boundaries for material retained by TryStore. |
| [License](../LICENSE) | Repository license text. |

## Guides

| Document | Purpose |
| --- | --- |
| [Patch workspace guide](PATCH_GUIDE.md) | Bundle-based workspace layout, apply/restore, passwords, and path-safety rules. |
| [Vietnamese patch workspace guide](PATCH_GUIDE.vi.md) | Vietnamese version of the patch workspace guide. |
| [Generated assets](HIGGSFIELD_ASSETS.md) | Higgsfield Worker, CLI script, model allowlist, cost table and security posture for art assets. |
| [eSign setup](ESIGN_SETUP.md) | Owner-controlled signing inputs, unsigned IPA validation, and installation workflow. |
| [1.0.1 release notes](releases/1.0.1.md) | Vietnamese release notes adapted for TryStore. |
| [Test1 project documentation reference](test1-reference/README.md) | Linked, TryStore-adapted documentation from the supplied test1 archive. |

## Archive documentation disposition

The supplied archive was read in full for README, guide, changelog, notice, and vendored-license content. The compatible patch-workspace material is incorporated above. The archive’s SupportPatch identity, device-exploit implementation notes, kernel/sandbox components, anti-detection material, game-modification controls, binary assets, and unrelated Rust-core vendor documentation are not copied into TryStore because they do not describe or belong to TryStore’s preserved GUI and cosmetic-only workflow.
