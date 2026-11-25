#!/bin/zsh
# Builds Athlos.app (app + macOS widget extension).
# - With Xcode: xcodegen + xcodebuild (including the widgets, with App Intents metadata).
# - Without Xcode: SwiftPM builds the app only (no widgets).
# Usage: scripts/build_app.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
[[ "${1:-}" == "--debug" ]] && CONFIG=Debug
APP=build/Athlos.app

if xcodebuild -version >/dev/null 2>&1; then
  # Build folder outside Desktop/iCloud: otherwise extended attributes break the signature.
  DERIVED="${TMPDIR:-/tmp/}athlos-derived"
  if command -v xcodegen >/dev/null 2>&1; then
    echo "▸ Generating the Xcode project (xcodegen)…"
    xcodegen generate --quiet
  fi
  echo "▸ Building (Xcode, $CONFIG)…"
  xcodebuild -project Athlos.xcodeproj -scheme Athlos -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' build -quiet
  rm -rf "$APP"
  mkdir -p build
  ditto "$DERIVED/Build/Products/$CONFIG/Athlos.app" "$APP"
  xattr -cr "$APP"
  codesign --verify --deep --strict "$APP"
  echo "✔ Done (with widgets): $(pwd)/$APP"
  exit 0
fi

# ---- Without Xcode: SwiftPM (the widget extension can't be built) ----
# In the macOS 27 SDK SwiftUI's @State is a macro; the Command Line Tools lack its plugin, so the 26.x SDK is used.
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi
CFG=$( [[ "$CONFIG" == "Debug" ]] && echo debug || echo release )
echo "▸ Building (SwiftPM, $CFG — no widgets)…"
swift build -c "$CFG" --arch arm64
BIN="$(swift build -c "$CFG" --arch arm64 --show-bin-path)/Athlos"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Athlos"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] || scripts/make_icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --deep --sign - --timestamp=none "$APP"
echo "✔ Done (no widgets): $(pwd)/$APP"
