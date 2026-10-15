#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported ARCH: $ARCH" >&2; exit 1;; esac
BUILD_DIR="${BUILD_DIR:-build}"
mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$BUILD_DIR/eqMini.app"
mkdir -p "$BUILD_DIR/objects" "$BUILD_DIR/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"

xcrun clang++ -std=c++17 -O2 -Wall -Wextra -Werror -fobjc-arc \
  -target "$ARCH-apple-macosx14.2" -isysroot "$SDK" \
  -c Sources/AudioEngine.mm -o "$BUILD_DIR/objects/AudioEngine.o"
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -target "$ARCH-apple-macosx14.2" -sdk "$SDK" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -import-objc-header Sources/AudioBridge.h Sources/*.swift "$BUILD_DIR/objects/AudioEngine.o" \
  -o "$APP/Contents/MacOS/eqmini" -framework SwiftUI -framework AppKit -framework CoreAudio -framework ServiceManagement -lc++
xcrun swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/BrandIcon.swift scripts/make-icon.swift -o "$BUILD_DIR/make-icon"
"$BUILD_DIR/make-icon" "$BUILD_DIR/AppIcon.iconset"
xcrun iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Info.plist)
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built ($ARCH, ad-hoc signed): $APP"
