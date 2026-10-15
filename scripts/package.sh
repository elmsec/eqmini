#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PREVIEW=0
if [[ "${1:-}" == --preview && $# == 1 ]]; then
  PREVIEW=1
elif [[ $# != 0 ]]; then
  echo 'Usage: bash scripts/package.sh [--preview]' >&2; exit 1
fi
if [[ "$PREVIEW" == 0 ]]; then
  : "${CODESIGN_IDENTITY:?Set a Developer ID Application identity or use --preview}"
  : "${NOTARY_PROFILE:?Set a notarytool keychain profile or use --preview}"
  [[ "$CODESIGN_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'A Developer ID Application certificate is required.' >&2; exit 1; }
fi
APP=build/eqmini.app
[[ -d "$APP" ]] || { echo 'Build the app first.' >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/eqmini" | tr ' ' '-')
NAME="eqmini-$VERSION-$ARCH"
[[ "$PREVIEW" == 0 ]] || NAME="$NAME-preview"
OUT="$PWD/release"
mkdir -p "$OUT"
STAGE=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/eqmini.app"
if [[ "$PREVIEW" == 0 ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp --entitlements Eqmini.entitlements "$STAGE/eqmini.app"
  ditto -c -k --sequesterRsrc --keepParent "$STAGE/eqmini.app" "$STAGE/notary.zip"
  xcrun notarytool submit "$STAGE/notary.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$STAGE/eqmini.app"
  xcrun stapler validate "$STAGE/eqmini.app"
fi
codesign --verify --deep --strict "$STAGE/eqmini.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/eqmini.app" "$OUT/$NAME.zip"
mkdir "$STAGE/disk"
ditto "$STAGE/eqmini.app" "$STAGE/disk/eqmini.app"
ln -s /Applications "$STAGE/disk/Applications"
cp LICENSE "$STAGE/disk/LICENSE.txt"
if [[ "$PREVIEW" == 1 ]]; then
  cat > "$STAGE/disk/READ ME.txt" <<'NOTICE'
eqmini preview — macOS 14.2+

Drag eqmini into Applications.

This preview is ad-hoc signed and NOT notarized. macOS may block downloaded
copies. Only proceed if you trust this source. Apple's per-app Open Anyway
option is in System Settings > Privacy & Security. Do not disable Gatekeeper.

System Audio Recording permission is needed when you enable EQ.
Privacy: https://elma.dev/eqmini/privacy
Terms: https://elma.dev/eqmini/terms
NOTICE
fi
hdiutil create -volname eqmini -srcfolder "$STAGE/disk" -ov -format UDZO "$OUT/$NAME.dmg"
if [[ "$PREVIEW" == 0 ]]; then
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$OUT/$NAME.dmg"
  xcrun notarytool submit "$OUT/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT/$NAME.dmg"
  xcrun stapler validate "$OUT/$NAME.dmg"
fi
(cd "$OUT" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME-SHA256SUMS.txt")
echo "Packaged: $OUT/$NAME.{zip,dmg}"
