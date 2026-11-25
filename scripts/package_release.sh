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

# Package from a clean copy outside Desktop/iCloud: those folders add extended attributes
# (FinderInfo, fileprovider) that make `codesign --verify --strict` fail ("detritus not allowed"),
# and a downloaded copy could then be reported as damaged.
STAGE="$(mktemp -d)"
ditto --norsrc --noextattr build/Athlos.app "$STAGE/Athlos.app"
xattr -cr "$STAGE/Athlos.app"
codesign --verify --deep --strict "$STAGE/Athlos.app"
echo "▸ Signature verified on the clean copy"

echo "▸ Zipping…"
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --keepParent Athlos.app "$OLDPWD/$OUT/Athlos-macOS.zip")

echo "▸ Creating the disk image…"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Athlos" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Athlos-macOS.dmg"
rm -rf "$STAGE"

(cd "$OUT" && shasum -a 256 Athlos-macOS.dmg Athlos-macOS.zip > SHA256SUMS.txt)
echo "✔ Release files:"
ls -lh "$OUT"
