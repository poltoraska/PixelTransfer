#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/pixel-explorer-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/ExplorerTests.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources/Libraries.bundle"
xcrun clang -dynamiclib -I MyApp/Native -I Tests Tests/MockExplorerMTP.c -o "$app/Resources/Libraries.bundle/libmtp.9.dylib"
xcrun clang -fobjc-arc -fblocks -framework Foundation -I MyApp/Native MyApp/Native/MTPBridge.m Tests/ExplorerBridgeTests.m -o "$app/MacOS/ExplorerTests"
"$app/MacOS/ExplorerTests"
