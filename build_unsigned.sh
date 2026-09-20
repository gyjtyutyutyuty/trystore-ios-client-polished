#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 127
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/ThreeOneOSFive.xcodeproj"
SCHEME="3105"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/3105.xcarchive"
IPA="$BUILD_DIR/3105-unsigned.ipa"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

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

APP="$ARCHIVE/Products/Applications/3105.app"
if [[ ! -d "$APP" ]]; then
  echo "Error: expected archived app at $APP" >&2
  exit 1
fi

# Keep bundled patch resources in the same Patches folder used by the runtime loader.
PATCH_DIR="$APP/Patches"
mkdir -p "$PATCH_DIR"
shopt -s nullglob
packages=("$APP"/*.3105)
if (( ${#packages[@]} == 0 )); then
  echo "Error: no .3105 patch packages were copied into the archived app." >&2
  exit 1
fi
for package in "${packages[@]}"; do
  mv "$package" "$PATCH_DIR/"
done
shopt -u nullglob

for required in \
  'HOLOGRAMAARMAS.3105' \
  'HSPESSCOSO.3105' \
  'HS SLA PECHO.3105'; do
  if [[ ! -f "$PATCH_DIR/$required" ]]; then
    echo "Error: required patch package is missing from the app: $required" >&2
    exit 1
  fi
done

# Xcode can omit these keys from the processed plist in an unsigned archive.
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

printf 'Unsigned archive: %s\n' "$ARCHIVE"
printf 'Unsigned IPA:     %s\n' "$IPA"
