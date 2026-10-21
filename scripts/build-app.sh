#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# Universal 2 for both Apple Silicon and Intel Macs.
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="$PWD/dist/QuickNote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuickNote" "$APP/Contents/MacOS/QuickNote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p dist/AppIcon.iconset
swift scripts/make-icon.swift "$PWD/dist/AppIcon.iconset"
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/QuickNote"
echo "$APP"
