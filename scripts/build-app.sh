#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 1
fi

bash scripts/swift-tool.sh build --configuration "$configuration"
bin_path="$(bash scripts/swift-tool.sh build --configuration "$configuration" --show-bin-path)"
app="$PWD/dist/Good Gameble Games.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable by rename so an open development build keeps its
# original mapped binary until the user quits and reopens it.
staged_binary="$app/Contents/MacOS/.GGGMac-$$"
staged_info="$app/Contents/.Info-$$.plist"
trap 'rm -f "$staged_binary" "$staged_info"' EXIT
cp "$bin_path/GGGMac" "$staged_binary"
mv -f "$staged_binary" "$app/Contents/MacOS/GGGMac"
cp scripts/Info.plist "$staged_info"
mv -f "$staged_info" "$app/Contents/Info.plist"
cp Sources/GGGMacCore/Resources/GGGMacGraphicsProbe.exe "$app/Contents/Resources/GGGMacGraphicsProbe.exe"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/licenses"
cp licenses/*.txt "$app/Contents/Resources/licenses/"
identity="${GGGMAC_CODESIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"
echo "Built: $app"
