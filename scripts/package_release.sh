#!/bin/zsh
# Builds Athlos and packages it for a GitHub release:
#   build/release/Athlos-macOS.dmg   (drag-to-Applications disk image)
#   build/release/Athlos-macOS.zip   (the app, zipped)
# The file names are fixed so "latest release" download links keep working.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build_app.sh

OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Zipping…"
ditto -c -k --sequesterRsrc --keepParent build/Athlos.app "$OUT/Athlos-macOS.zip"

echo "▸ Creating the disk image…"
STAGE="$(mktemp -d)"
ditto build/Athlos.app "$STAGE/Athlos.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Athlos" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Athlos-macOS.dmg"
rm -rf "$STAGE"

(cd "$OUT" && shasum -a 256 Athlos-macOS.dmg Athlos-macOS.zip > SHA256SUMS.txt)
echo "✔ Release files:"
ls -lh "$OUT"
