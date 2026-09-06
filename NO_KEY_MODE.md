# Temporary local access mode

The main SwiftUI console currently runs with `licenseGateEnabled = false` in `ThreeOneOSFive/ContentView.swift`. Patch activation no longer requires a license key, while the device-integrity check remains enforced before protected actions.

The license manager files remain in the project so the gate can be re-enabled later by changing that flag to `true` and restoring the license panel in the view flow.

## Build note

An IPA must be built on macOS with Xcode installed. Run `./build_unsigned.sh` from the project root, then validate the resulting unsigned IPA with `./build_esign_ready_ipa.sh` before signing it for a device.
