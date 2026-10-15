# Contributing

Start with an issue describing the behavior you want to change. For a bug, include the macOS version, Mac model, output device, audio source app, routing mode, and steps to reproduce. Do not attach captured audio or private process listings unless you intend to share them.

## Local work

1. Build with `bash scripts/build.sh`.
2. Run `bash scripts/test.sh`; use `SANITIZE=1 bash scripts/test.sh` for DSP changes.
3. Check the affected UI in both Simple and 10-band views. Keep your app bypassed when testing layout only.
4. For routing changes, run the opt-in checks in [TESTING.md](docs/TESTING.md).

Use `xcrun swift-format format --in-place --recursive Sources Tests` to format Swift. C++ uses C++17 and must pass `-Wall -Wextra -Werror`. Keep pull requests focused, explain the user-visible result, and record what was actually tested.

## Constraints worth preserving

- No allocation, locks, logging, Objective-C calls, or file/network I/O in the audio callback.
- Create/destroy routes and enumerate audio processes on the serialized audio-control queue.
- An empty selected-app list must never capture all audio.
- Closing a window must not stop processing; Quit must release the route.
- Switching editor views must preserve the exact EQ curve.
- Login launch and restoring EQ remain separate, opt-in preferences.
- Do not introduce telemetry, recording, or permissions without an explicit product decision and corresponding privacy documentation.

Contributions are licensed under the project's MIT license. Do not include signing certificates, private keys, account tokens, copied proprietary code, or unlicensed assets.
