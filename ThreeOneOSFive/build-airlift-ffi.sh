#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/airlift-rust-core"
OUTPUT="$ROOT/AirliftFFI.xcframework"
TEMP_OUTPUT="$ROOT/AirliftFFI.tmp.xcframework"

# The repository contains the exact device and simulator XCFrameworks needed by
# the Xcode target. This keeps CI independent of Rust target installation,
# crates.io/Git access, and the host's local Rust toolchain. Set
# REBUILD_AIRLIFT=1 on macOS when intentionally rebuilding the framework.
REBUILD_AIRLIFT="${REBUILD_AIRLIFT:-0}"

if [[ "$REBUILD_AIRLIFT" != "1" ]]; then
  test -s "$OUTPUT/ios-arm64/libairlift_ffi.a" || {
    echo "AirliftFFI.xcframework is missing the ios-arm64 library; run with REBUILD_AIRLIFT=1 on macOS." >&2
    exit 1
  }
  test -s "$OUTPUT/ios-arm64-simulator/libairlift_ffi.a" || {
    echo "AirliftFFI.xcframework is missing the simulator library; run with REBUILD_AIRLIFT=1 on macOS." >&2
    exit 1
  }
  test -f "$OUTPUT/Info.plist" || {
    echo "AirliftFFI.xcframework is missing Info.plist; run with REBUILD_AIRLIFT=1 on macOS." >&2
    exit 1
  }
  echo "Using committed AirliftFFI.xcframework (set REBUILD_AIRLIFT=1 to rebuild)."
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REBUILD_AIRLIFT=1 requires macOS because Rust iOS targets and xcodebuild are Apple-only." >&2
  exit 1
fi

command -v rustup >/dev/null 2>&1 || { echo "rustup is required for an Airlift rebuild." >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "cargo is required for an Airlift rebuild." >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required for an Airlift rebuild." >&2; exit 1; }
source "$HOME/.cargo/env" 2>/dev/null || true
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

cargo build --locked --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios
cargo build --locked --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios-sim

test -s "$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a"
test -s "$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a"

rm -rf "$TEMP_OUTPUT"
xcodebuild -create-xcframework \
  -library "$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -library "$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -output "$TEMP_OUTPUT"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT" "$OUTPUT"
echo "Rebuilt $OUTPUT"
