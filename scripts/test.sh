#!/bin/zsh
# Runs the AthlosCore unit tests (swift-testing).
# - ATHLOS_CORE_ONLY=1: the SwiftUI app target is left out (Command Line Tools have no SwiftUI macro plugin).
# - Without Xcode, the swift-testing macro plugin is passed explicitly from the Command Line Tools.
# - Build folder in TMPDIR: Desktop/iCloud extended attributes would break signing the test bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA=()
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if ! xcodebuild -version >/dev/null 2>&1 && [[ -d "$PLUGINS" ]]; then
  EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

ATHLOS_CORE_ONLY=1 swift test --scratch-path "${TMPDIR:-/tmp/}athlos-tests" "${EXTRA[@]}" "$@"
