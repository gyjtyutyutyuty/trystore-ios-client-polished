#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 127
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/3105.xcarchive"
IPA="$BUILD_DIR/3105-unsigned.ipa"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT/ThreeOneOSFive.xcodeproj" \
  -scheme 3105 \
  -configuration Release \
  -sdk iphoneos \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

APP="$ARCHIVE/Products/Applications/3105.app"
test -d "$APP"

# Keep patch resources in the same Patches folder used by the runtime loader.
PATCH_DIR="$APP/Patches"
mkdir -p "$PATCH_DIR"
for package in "$APP"/*.3105; do
  [ -e "$package" ] || continue
  mv "$package" "$PATCH_DIR/"
done
test -n "$(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.3105' -print -quit)"

# Xcode can omit these keys from the processed plist in the unsigned archive.
# eSign importers use them to identify the executable app bundle.
plutil -replace CFBundleExecutable -string 3105 "$APP/Info.plist"
plutil -replace CFBundlePackageType -string APPL "$APP/Info.plist"

mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
(
  cd "$BUILD_DIR"
  /usr/bin/zip -qry "$IPA" Payload
  rm -rf Payload
)

echo "Unsigned archive: $ARCHIVE"
echo "Unsigned IPA:     $IPA"
