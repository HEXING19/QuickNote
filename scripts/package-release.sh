#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
PACKAGE_NAME="QuickNote-${VERSION}-universal"
RELEASE_DIR="$PWD/dist/release"
STAGING_DIR=$(mktemp -d "$PWD/dist/dmg-staging.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$RELEASE_DIR"
ditto dist/QuickNote.app "$STAGING_DIR/QuickNote.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "QuickNote ${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$RELEASE_DIR/${PACKAGE_NAME}.dmg"
ditto -c -k --keepParent dist/QuickNote.app "$RELEASE_DIR/${PACKAGE_NAME}.zip"
(cd "$RELEASE_DIR" && shasum -a 256 "${PACKAGE_NAME}.dmg" "${PACKAGE_NAME}.zip" > SHA256SUMS.txt)
echo "$RELEASE_DIR"
