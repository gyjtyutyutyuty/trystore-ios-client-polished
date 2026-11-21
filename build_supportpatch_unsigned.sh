#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/ThreeOneOSFive.xcodeproj"
SCHEME="SupportPatch"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/SupportPatch.xcarchive"
IPA="$BUILD_DIR/SupportPatch-unsigned.ipa"
PATCH_FEED_URL="${PATCH_FEED_URL:-https://trystore-patch-feed.burgoajustin.workers.dev}"
PRESEALED="$ROOT/build_support/CharacterVaultTSC2/CharacterVault"
PRESEALED_MANIFEST="$ROOT/build_support/CharacterVaultTSC2/manifest.json"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 127
fi

VAULT_MODE="key"
if [[ -z "${TRYSTORE_BUNDLE_KEY:-}" ]]; then
  if [[ "${ALLOW_TSC1_VAULT:-0}" == "1" ]]; then
    VAULT_MODE="tsc1"
  elif [[ -d "$PRESEALED" && -f "$PRESEALED_MANIFEST" ]]; then
    VAULT_MODE="presealed"
  else
    echo "Error: set TRYSTORE_BUNDLE_KEY or commit the pre-sealed vault." >&2
    exit 1
  fi
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# The checked-in XCFramework may lag behind the Rust FFI surface. Rebuild it
# before Xcode links the app; set REBUILD_AIRLIFT=0 to only validate the archive.
REBUILD_AIRLIFT="${REBUILD_AIRLIFT:-1}" bash "$ROOT/ThreeOneOSFive/build-airlift-ffi.sh"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

APP="$ARCHIVE/Products/Applications/SupportPatch.app"
if [[ ! -d "$APP" ]]; then
  echo "Error: expected archived app at $APP" >&2
  exit 1
fi

# Release art must not carry the historical static TSC1 key. Prefer the
# server-released key when the build has it; otherwise use the checked-in
# pre-sealed vault, but only if it matches the fingerprint the feed serves.
if [[ "$VAULT_MODE" == "key" ]]; then
  python3 "$ROOT/scripts/rewrap_character_vault.py" \
    --app "$APP" --bundle-key "$TRYSTORE_BUNDLE_KEY"
elif [[ "$VAULT_MODE" == "tsc1" ]]; then
  echo "Warning: shipping TSC1 CharacterVault (ALLOW_TSC1_VAULT=1)" >&2
else
  if ! FEED_FINGERPRINT="$(
    curl -fsS --max-time 20 \
      "$PATCH_FEED_URL/api/patches/trystore/bundle-key/fingerprint" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])'
  )" || [[ -z "$FEED_FINGERPRINT" ]]; then
    echo "Error: cannot read the feed key fingerprint from $PATCH_FEED_URL." >&2
    exit 1
  fi
  rm -rf "$APP/CharacterVault"
  cp -R "$PRESEALED" "$APP/CharacterVault"
  python3 "$ROOT/scripts/verify_presealed_vault.py" \
    --vault "$APP/CharacterVault" \
    --manifest "$PRESEALED_MANIFEST" \
    --fingerprint "$FEED_FINGERPRINT"
fi

python3 "$ROOT/scripts/verify_legacy_patch_bundle.py" --app "$APP"
plutil -replace CFBundleExecutable -string SupportPatch "$APP/Info.plist"
plutil -replace CFBundlePackageType -string APPL "$APP/Info.plist"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
(
  cd "$BUILD_DIR"
  /usr/bin/zip -qry "$IPA" Payload
  rm -rf Payload
)

printf 'Unsigned archive: %s\n' "$ARCHIVE"
printf 'Unsigned IPA:     %s\n' "$IPA"
