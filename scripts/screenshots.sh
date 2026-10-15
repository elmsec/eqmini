#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f build/objects/AudioEngine.o ]] || { echo 'Build the app first.' >&2; exit 1; }
mkdir -p build/module-cache
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=()
for source in Sources/*.swift; do
  [[ "$source" == Sources/EqminiApp.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.2" \
  -sdk "$SDK" -module-cache-path "$PWD/build/module-cache" -import-objc-header Sources/AudioBridge.h \
  "${SOURCES[@]}" Tests/DocumentationScreenshots.swift build/objects/AudioEngine.o \
  -o build/documentation-screenshots -framework SwiftUI -framework AppKit -framework CoreAudio -framework ServiceManagement -lc++
# Give the renderer the shipping version metadata without using production preferences.
RUNNER="$PWD/build/screenshot-runner.app"
mkdir -p "$RUNNER/Contents/MacOS"
cp build/documentation-screenshots "$RUNNER/Contents/MacOS/documentation-screenshots"
cp Info.plist "$RUNNER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable documentation-screenshots' "$RUNNER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.elma.eqmini.screenshot-renderer' "$RUNNER/Contents/Info.plist"
codesign --force --sign - "$RUNNER"
"$RUNNER/Contents/MacOS/documentation-screenshots" "$PWD/docs/screenshots"
