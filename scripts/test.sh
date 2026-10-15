#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-std=c++17 -O2 -Wall -Wextra -Werror)
if [[ "${SANITIZE:-0}" == 1 ]]; then
  FLAGS+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
xcrun clang++ "${FLAGS[@]}" Tests/DSPTests.cpp -o build/tests/dsp-tests
build/tests/dsp-tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra -Werror -fobjc-arc -mmacosx-version-min=14.2 -isysroot "$SDK" \
  -c Sources/AudioEngine.mm -o build/tests/AudioEngine.o
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.2" -sdk "$SDK" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -import-objc-header Sources/AudioBridge.h Sources/EqualizerModel.swift Sources/StartupSettings.swift Tests/SettingsTests.swift \
  build/tests/AudioEngine.o -o build/tests/settings-tests -framework AppKit -framework CoreAudio -framework ServiceManagement -lc++
build/tests/settings-tests --settings-self-test
build/tests/settings-tests --startup-self-test
