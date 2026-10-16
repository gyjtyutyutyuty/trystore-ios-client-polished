#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/airlift-rust-core"
OUTPUT="$ROOT/AirliftFFI.xcframework"
TEMP_OUTPUT="$ROOT/AirliftFFI.tmp.xcframework"

# The repository contains a framework for quick local builds. CI should set
# REBUILD_AIRLIFT=1 so the framework is regenerated whenever the Rust FFI
# surface changes. This prevents stale archives from silently missing exports.
REBUILD_AIRLIFT="${REBUILD_AIRLIFT:-0}"

required_exports=(
  al_log_init
  al_pairing_run_host
  al_exploit_run
  al_exploit_write_dir
  al_exploit_read_file
  al_exploit_inject_folder
  al_find_app_container
  al_device_respring
)

has_export() {
  local archive="$1"
  local symbol="$2"
  if command -v nm >/dev/null 2>&1 && nm -gU "$archive" 2>/dev/null | grep -Eq "(^|[[:space:]])_?${symbol}([[:space:]]|$)"; then
    return 0
  fi
  # GNU nm cannot inspect the Mach-O archive in the Linux sandbox; this fallback
  # still catches missing symbol names in committed/generated archives.
  grep -a -q "$symbol" "$archive"
}

has_stale_grappa_lookup() {
  local archive="$1"
  # Older archives resolved the app-owned helper with dlsym(RTLD_DEFAULT).
  # That lookup is not reliable once the iOS 27 linker strips the symbol.
  # The current Rust implementation uses a direct external reference instead.
  grep -a -q 'ALGetGrappaToken symbol not found' "$archive"
}

verify_archive() {
  local archive="$1"
  test -s "$archive" || return 1
  for symbol in "${required_exports[@]}"; do
    if ! has_export "$archive" "$symbol"; then
      echo "Airlift archive is missing required export: $symbol" >&2
      return 1
    fi
  done
  if has_stale_grappa_lookup "$archive"; then
    echo "Airlift archive contains the stale dynamic Grappa lookup; rebuild it from current sources." >&2
    return 1
  fi
}

if [[ "$REBUILD_AIRLIFT" != "1" ]]; then
  verify_archive "$OUTPUT/ios-arm64/libairlift_ffi.a" || {
    echo "The committed Airlift framework is stale or incomplete; run REBUILD_AIRLIFT=1 on macOS." >&2
    exit 1
  }
  verify_archive "$OUTPUT/ios-arm64-simulator/libairlift_ffi.a" || {
    echo "The committed Airlift simulator framework is stale or incomplete; run REBUILD_AIRLIFT=1 on macOS." >&2
    exit 1
  }
  test -f "$OUTPUT/Info.plist"
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
for archive in \
  "$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a" \
  "$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a"; do
  if ! verify_archive "$archive"; then
    echo "Warning: symbol inspection could not confirm every export in $archive; Xcode's app link will validate required symbols." >&2
  fi
done

rm -rf "$TEMP_OUTPUT"
xcodebuild -create-xcframework \
  -library "$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -library "$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -output "$TEMP_OUTPUT"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT" "$OUTPUT"
for archive in \
  "$OUTPUT/ios-arm64/libairlift_ffi.a" \
  "$OUTPUT/ios-arm64-simulator/libairlift_ffi.a"; do
  if ! verify_archive "$archive"; then
    echo "Warning: symbol inspection could not confirm every export in $archive; Xcode's app link will validate required symbols." >&2
  fi
done
echo "Rebuilt $OUTPUT; Xcode will validate the app's required FFI symbols at link time."
