#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/macos/Kleam"
app="$root/dist/Kleam.app"
bin="$app/Contents/MacOS"
res="$app/Contents/Resources"

rm -rf "$app"
mkdir -p "$bin" "$res"
cp "$src/Info.plist" "$app/Contents/Info.plist"

# Nested sound packs: sounds/{slug}/{down,up}-N.wav + mouse-*.wav
if [[ -d "$src/Resources/sounds" ]]; then
  ditto "$src/Resources/sounds" "$res/sounds"
fi
# Legacy flat wavs (if any remain alongside nested packs).
if compgen -G "$src/Resources/"*.wav > /dev/null; then
  cp "$src/Resources/"*.wav "$res/"
fi

# App icon: rebuild .icns from iconset when present, then copy into the bundle.
iconset="$src/AppIcon.iconset"
icns="$src/AppIcon.icns"
if [[ -d "$iconset" ]]; then
  iconutil -c icns "$iconset" -o "$icns" || true
fi
if [[ -f "$icns" ]]; then
  cp "$icns" "$res/AppIcon.icns"
fi

sdk="$(xcrun --sdk macosx --show-sdk-path)"
swiftc \
  -sdk "$sdk" \
  -target arm64-apple-macosx14.0 \
  -O \
  -swift-version 5 \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework IOKit \
  -o "$bin/Kleam" \
  "$src/KleamApp.swift" \
  "$src/AppModel.swift" \
  "$src/SoundEngine.swift" \
  "$src/HIDKeys.swift" \
  "$src/SwitchCatalog.swift" \
  "$src/MenuView.swift"

codesign --force --sign - "$app"
echo "Built $app"
