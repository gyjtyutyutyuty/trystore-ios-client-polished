# License-gated access mode

The main SwiftUI console currently runs with `licenseGateEnabled = true` in `ThreeOneOSFive/ContentView.swift`. Protected patch activation requires an active license key, while the device-integrity check remains enforced before protected actions.

The license manager and license panel remain in the project and are active in the current TryStore workflow.

## Build note

An IPA must be built on macOS with Xcode installed. Run `./build_unsigned.sh` from the project root, then validate the resulting unsigned IPA with `./build_esign_ready_ipa.sh` before signing it for a device.
