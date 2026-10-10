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
  COMPILATION_CACHE_ENABLE_CACHING=YES \
  archive

APP="$ARCHIVE/Products/Applications/SupportPatch.app"
if [[ ! -d "$APP" ]]; then
  echo "Error: expected archived app at $APP" >&2
  exit 1
fi

python3 "$ROOT/scripts/verify_legacy_patch_bundle.py" --app "$APP"
plutil -replace CFBundleExecutable -string SupportPatch "$APP/Info.plist"
plutil -replace CFBundlePackageType -string APPL "$APP/Info.plist"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
(
  cd "$BUILD_DIR"
  # ditto creates the conventional Apple IPA ZIP with Payload at archive root.
  /usr/bin/ditto -c -k --norsrc --keepParent Payload "$IPA"
  rm -rf Payload
)

/usr/bin/unzip -tq "$IPA"
python3 - "$IPA" <<'PY'
import plistlib
import sys
import zipfile

ipa = sys.argv[1]
with zipfile.ZipFile(ipa) as archive:
    names = set(archive.namelist())
    app_infos = [name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist")]
    if len(app_infos) != 1:
        raise SystemExit(f"Expected exactly one Payload/*.app/Info.plist, found {app_infos!r}")
    info_path = app_infos[0]
    app_root = info_path.removesuffix("Info.plist")
    metadata = plistlib.loads(archive.read(info_path))
    executable = metadata.get("CFBundleExecutable")
    if metadata.get("CFBundlePackageType") != "APPL" or not executable:
        raise SystemExit("The IPA app Info.plist is missing a valid APPL package type or executable name")
    if app_root + executable not in names:
        raise SystemExit(f"The IPA is missing its declared executable: {app_root}{executable}")
    if any(not (name == "Payload/" or name.startswith("Payload/")) for name in names):
        raise SystemExit("The IPA contains files outside the top-level Payload directory")
print(f"Validated eSign-ready IPA layout: {info_path}")
PY

printf 'Unsigned archive: %s\n' "$ARCHIVE"
printf 'Unsigned IPA:     %s\n' "$IPA"
