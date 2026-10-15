#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f build/objects/AudioEngine.o && -d build/eqMini.app ]] || { echo 'Build the app first.' >&2; exit 1; }
RUNNER="$PWD/build/launch-tests.app"
mkdir -p "$RUNNER/Contents/MacOS"
SDK=$(xcrun --sdk macosx --show-sdk-path)
SOURCES=()
for source in Sources/*.swift; do
  [[ "$source" == Sources/EqminiApp.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -Onone -warnings-as-errors -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.2" -sdk "$SDK" -module-cache-path "$PWD/build/module-cache" \
  -import-objc-header Sources/AudioBridge.h "${SOURCES[@]}" Tests/LaunchServicesTests.swift \
  build/objects/AudioEngine.o -o "$RUNNER/Contents/MacOS/launch-tests" \
  -framework SwiftUI -framework AppKit -framework CoreAudio -framework ServiceManagement -lc++
cp Info.plist "$RUNNER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable launch-tests' "$RUNNER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.elma.eqmini.launch-tests' "$RUNNER/Contents/Info.plist"
codesign --force --sign - "$RUNNER"
for mode in first repeat login; do
  report="$PWD/build/launch-$mode.json"
  args=(--report "$report")
  [[ "$mode" != repeat ]] || args+=(--previously-opened)
  [[ "$mode" != login ]] || args+=(--login-launch)
  open -n -W "$RUNNER" --args "${args[@]}"
  python3 - "$report" "$mode" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    report = json.load(f)
assert report['passed'], report
print('PASS: Launch Services', sys.argv[2], 'launch; window visible =', report['expectedWindow'])
PY
done
