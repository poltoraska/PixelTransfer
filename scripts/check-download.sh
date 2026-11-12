#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/pixel-download-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcrun swiftc -module-cache-path "$work/cache" MyApp/DownloadPlan.swift Tests/DownloadPlanTests.swift -o "$work/plan-tests"
"$work/plan-tests"
app="$work/DownloadBridgeTests.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources/Libraries.bundle"
xcrun clang -dynamiclib -I MyApp/Native Tests/MockMTP.c -o "$app/Resources/Libraries.bundle/libmtp.9.dylib"
xcrun clang -fobjc-arc -fblocks -framework Foundation -I MyApp/Native MyApp/Native/MTPBridge.m Tests/DownloadBridgeTests.m -o "$app/MacOS/DownloadBridgeTests"
"$app/MacOS/DownloadBridgeTests"
