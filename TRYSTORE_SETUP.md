# SupportPatch project setup

The repository now uses the uploaded `test1-main` project as its source of truth. The application target is **SupportPatch**, with the shared scheme at `ThreeOneOSFive.xcodeproj/xcshareddata/xcschemes/SupportPatch.xcscheme`.

## Included in the merge

- SupportPatch GUI and Files/patch-workspace flows under `ThreeOneOSFive/`.
- Airlift FFI XCFramework at `ThreeOneOSFive/AirliftFFI.xcframework`.
- Airlift Rust-core rebuild script at `ThreeOneOSFive/build-airlift-ffi.sh` (the committed XCFramework is used by default; set `REBUILD_AIRLIFT=1` to rebuild on macOS).
- Current bundled patch datasets under `ThreeOneOSFive/Assets.xcassets/**/*.dataset/*.bin`.
- Encrypted `.3105` package import/export for user-created patch projects.

Legacy root GUI files, old standalone `.3105` binaries, and their build checks were removed. The CI workflow now validates the SupportPatch target, Airlift framework, current `.bin` datasets, and absence of legacy bundled `.3105` files.

## Build

```bash
chmod +x ./ThreeOneOSFive/build-airlift-ffi.sh ./build_supportpatch_unsigned.sh
./ThreeOneOSFive/build-airlift-ffi.sh
./build_supportpatch_unsigned.sh
```

See [BUILD_ON_MAC.md](BUILD_ON_MAC.md), [README.md](README.md), and [docs/PATCH_GUIDE.md](docs/PATCH_GUIDE.md) for the complete workflow.
