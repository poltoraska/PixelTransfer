#!/bin/sh
# Build a local Release DMG, or package an already signed app passed as argument.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [path/to/PixelTransfer.app]" >&2
    exit 2
fi
background_source="$project_dir/PixelTransferBackground.png"
if [ ! -f "$background_source" ]; then
    echo "Missing background: $background_source" >&2
    exit 1
fi
mkdir -p .build dist
if [ "$#" -eq 0 ]; then
    build_log="$project_dir/.build/dmg-release-build.log"
    echo "Building PixelTransfer Release…"
    if ! xcodebuild -project PixelTransfer.xcodeproj -scheme PixelTransfer \
        -configuration Release -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath .build build > "$build_log" 2>&1; then
        tail -n 80 "$build_log" >&2
        exit 1
    fi
    application="$project_dir/.build/Build/Products/Release/PixelTransfer.app"
else
    application=$(CDPATH= cd -- "$1" && pwd)
fi
if [ ! -f "$application/Contents/Info.plist" ]; then
    echo "Missing macOS app bundle: $application" >&2
    exit 1
fi
codesign --verify --deep --strict "$application"
if [ ! -x .build/dmg-tools/bin/python ]; then
    python3 -m venv .build/dmg-tools
fi
if ! .build/dmg-tools/bin/python -c 'import dmgbuild; from importlib.metadata import version; assert version("dmgbuild") == "1.6.7"' 2>/dev/null; then
    .build/dmg-tools/bin/python -m pip install --disable-pip-version-check 'dmgbuild==1.6.7'
fi
package_dir=$(mktemp -d "$project_dir/.build/dmg-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Both TIFF representations have the same logical size, retaining Retina detail.
sips -s format tiff -z 536 960 -s dpiWidth 72 -s dpiHeight 72 \
    "$background_source" --out "$package_dir/background-1x.tiff" >/dev/null
sips -s format tiff -z 1072 1920 -s dpiWidth 144 -s dpiHeight 144 \
    "$background_source" --out "$package_dir/background-2x.tiff" >/dev/null
tiffutil -cathidpicheck "$package_dir/background-1x.tiff" \
    "$package_dir/background-2x.tiff" -out "$package_dir/background.tiff" >/dev/null
app_version=$(plutil -extract CFBundleShortVersionString raw -o - "$application/Contents/Info.plist")
case "$app_version" in
    ''|*[!0-9A-Za-z._-]*) echo "Invalid version for output filename" >&2; exit 1 ;;
esac
output="$project_dir/dist/PixelTransfer-$app_version-arm64.dmg"
echo "Creating disk image…"
.build/dmg-tools/bin/dmgbuild -s scripts/dmg-settings.py \
    -D "app=$application" -D "background=$package_dir/background.tiff" \
    PixelTransfer "$package_dir/PixelTransfer.dmg"
hdiutil verify "$package_dir/PixelTransfer.dmg"
.build/dmg-tools/bin/python scripts/verify-dmg.py "$package_dir/PixelTransfer.dmg" "$application"
mv -f "$package_dir/PixelTransfer.dmg" "$output"
echo "Created: $output"
