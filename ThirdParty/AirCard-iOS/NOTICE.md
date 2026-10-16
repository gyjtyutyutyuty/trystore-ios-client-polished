# AirCard-iOS compatibility code

Upstream: [Mak5er/AirCard-iOS](https://github.com/Mak5er/AirCard-iOS)
Reviewed upstream commit: `40640c4d827aeab8d798285b57d24fcf6be070d0`
License: MIT; see [LICENSE](LICENSE).

Adapted components: Airlift target-host discovery and RSD/Lockdown tunnel fallback, plus dynamic Grappa token symbol lookup. The upstream Wallet skin/theme UI is not embedded in this app; existing app features and the remote-read/rollback FFI remain intact.

After these Rust source changes, rebuild the iOS device and simulator frameworks on macOS with `REBUILD_AIRLIFT=1 ./ThreeOneOSFive/build-airlift-ffi.sh` before building the app.
