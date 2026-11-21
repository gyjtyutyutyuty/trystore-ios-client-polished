#!/usr/bin/env bash
set -euo pipefail

# The source meshes are developer-only fixtures. Production archives fetch the
# sealed vault after licence validation and must never contain these clear files.
if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  exit 0
fi

: "${SRCROOT:?Xcode did not provide SRCROOT}"
: "${TARGET_BUILD_DIR:?Xcode did not provide TARGET_BUILD_DIR}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?Xcode did not provide the app resource path}"

source_dir="$SRCROOT/ThreeOneOSFive/CharacterModels"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/CharacterModels"

if [[ ! -d "$source_dir" ]]; then
  echo "error: Debug character source assets are missing at $source_dir" >&2
  exit 1
fi

mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
cp -R "$source_dir" "$destination"
echo "Copied Debug-only character models to $destination"
