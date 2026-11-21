#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/ThreeOneOSFive.xcodeproj"
SCHEME="SupportPatch"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/SupportPatch.xcarchive"
IPA="$BUILD_DIR/SupportPatch-unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 127
fi

if [[ -z "${TRYSTORE_BUNDLE_KEY:-}" && "${ALLOW_TSC1_VAULT:-0}" != "1" ]]; then
  echo "Error: TRYSTORE_BUNDLE_KEY is required to seal CharacterVault for release." >&2
  echo "Set it in the build environment, or pass ALLOW_TSC1_VAULT=1 for a local Debug-only archive." >&2
  exit 1
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

# Release art must not carry the historical static TSC1 key. Re-seal every
# CharacterVault blob under the server-released bundle key. Local debug builds
# can opt out with ALLOW_TSC1_VAULT=1; CI and release archives cannot.
if [[ -n "${TRYSTORE_BUNDLE_KEY:-}" ]]; then
  python3 "$ROOT/scripts/rewrap_character_vault.py" \
    --app "$APP" --bundle-key "$TRYSTORE_BUNDLE_KEY"
elif [[ "${ALLOW_TSC1_VAULT:-0}" == "1" ]]; then
  echo "Warning: shipping TSC1 CharacterVault (ALLOW_TSC1_VAULT=1)" >&2
else
  echo "Error: TRYSTORE_BUNDLE_KEY is required to seal CharacterVault for release." >&2
  exit 1
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
