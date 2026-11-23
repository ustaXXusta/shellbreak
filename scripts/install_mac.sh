#!/usr/bin/env bash
# Builds Shellbreak (Release) outside Spotlight's reach and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="$HOME/Library/Caches/shellbreak-build"
mkdir -p "$BUILD" && touch "$BUILD/.metadata_never_index"
xcodegen generate >/dev/null
xcodebuild -scheme MacHost -destination 'platform=macOS' -configuration Release \
  -derivedDataPath "$BUILD" -allowProvisioningUpdates build | grep -E "error:|BUILD" || true
pkill -x Shellbreak || true
rm -rf /Applications/Shellbreak.app
ditto "$BUILD/Build/Products/Release/Shellbreak.app" /Applications/Shellbreak.app
echo "Installed /Applications/Shellbreak.app"
