#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/pixel-interface-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$work/cache" MyApp/InfoShortcutBridge.swift MyApp/AppAbout.swift Tests/InterfaceChecks.swift -o "$work/checks"
"$work/checks"
