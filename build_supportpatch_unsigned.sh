#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/ThreeOneOSFive.xcodeproj"
SCHEME="SupportPatch"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/SupportPatch.xcarchive"
IPA="$BUILD_DIR/SupportPatch-unsigned.ipa"
PATCH_FEED_URL="${PATCH_FEED_URL:-https://trystore-patch-feed.burgoajustin.workers.dev}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 127
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
exec > >(tee "$BUILD_DIR/build.log") 2>&1

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

# The character vault and patch payloads stay out of the archive. The feed
# serves the sealed vault to a licensed device; anything left here is one
# unzip away from Filza.
if [[ -e "$APP/CharacterVault" ]]; then
  echo "Error: CharacterVault is still bundled in the app." >&2
  exit 1
fi
if [[ -e "$APP/CharacterModels" ]]; then
  echo "Error: unsealed CharacterModels are still bundled in the app." >&2
  exit 1
fi
if [[ -e "$APP/Patches" ]]; then
  echo "Error: Patches is still bundled in the app." >&2
  exit 1
fi

python3 "$ROOT/scripts/verify_legacy_patch_bundle.py" --app "$APP"

# Pin the executable's code sections. The device recomputes this digest on
# launch; a patched build that rewrites code or constants no longer matches and
# the hardening gate clears the licence and the bundle key.
CODE_DIGEST="$(python3 "$ROOT/tools/macho_code_digest.py" "$APP/SupportPatch")"
if [[ -z "$CODE_DIGEST" ]]; then
  echo "Error: could not compute the executable code digest." >&2
  exit 1
fi
# `plutil -replace` refuses a missing key, so insert it on the first archive
# and replace it when an Info.plist already carries a previous pin.
if plutil -extract TRYSTORE_CODE_SHA256 raw "$APP/Info.plist" >/dev/null 2>&1; then
  plutil -replace TRYSTORE_CODE_SHA256 -string "$CODE_DIGEST" "$APP/Info.plist"
else
  plutil -insert TRYSTORE_CODE_SHA256 -string "$CODE_DIGEST" "$APP/Info.plist"
fi

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
