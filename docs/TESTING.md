# Testing

## Automated checks

```sh
bash scripts/build.sh
bash scripts/test.sh
SANITIZE=1 bash scripts/test.sh
codesign --verify --deep --strict build/eqMini.app
```

DSP tests cover flat response, bass contrast, full headroom compensation above 6 dB, output gain, harmonic generation, stereo isolation, invalid values, and bounded output at 44.1/48/96 kHz. Settings tests use an isolated preferences domain. Startup tests use fake login services; no real login item is registered or removed.

CI repeats the build and sanitized suite on native Apple silicon and Intel runners. Menu action tests verify that both enable menus pass through the explanation gate, cancellation disablees, and acceptance persists. Watchdog tests cover paused sources, stale/unknown activity, resumed callbacks, and sustained playback stalls. Hardware-dependent audio permission/capture checks are deliberately excluded from CI.

## Live audio checks (opt-in)

Quit the normal app first. These commands create a real audio route and require macOS audio permission. Start with comfortable playback volume. They do not save audio.

```sh
build/eqMini.app/Contents/MacOS/eqmini --audio-self-test
build/eqMini.app/Contents/MacOS/eqmini --audio-self-test --select-bundle com.spotify.client
```

The audio test runs three start/capture/stop cycles. It checks callback health, rendered frames, and that the default output remains unchanged. The selected-app test verifies the inclusive tap process list and that an empty list cannot start a global tap. The source app must already have registered an audio process. A nonzero input peak requires actual playback; rendered silent frames alone are not evidence that source audio was captured.

`--list-audio-apps` prints process metadata without creating a tap. Inspect it before sharing. `--control-self-test` exercises the asynchronous UI/control lifecycle using saved routing and may update the last enabled preference; use it only on a development installation.

## Manual release checks

- Download the actual release archive on a clean Mac; test extraction, Gatekeeper, and permission grant/denial.
- Check the first normal launch opens a window, later starts stay quiet, and login launch does not consume the welcome window, and left/right clicks on the menu-bar icon show the panel/menu.
- From each enable control, check the explanation appears before macOS permission on a new build; cancel must not start capture.
- Pause playback for at least 15 seconds in all-audio and selected-app modes; EQ must remain enabled without an error and resume processing when playback resumes.
- Enable and disable while audio plays; quit while enabled and confirm normal playback returns.
- Check selected Spotify/Music playback while an unselected browser remains unaffected. Test no selected apps, app restarts, and helper processes.
- Compare Simple and 10-band views, change presets, restore Custom, and reset individual bands/the entire EQ.
- Test headphones/Bluetooth, default-device changes, sample-rate changes, sleep/wake, and an unplugged device.
- Verify all content remains accessible on a small display and at the window's minimum height.
- Register launch at login from an installed app, log out/in, and confirm no window opens. Check both restore states, approval in System Settings, and removing the login item outside the app.

A simulated quiet launch (`--login-launch`) tests presentation only; it does not validate real OS login registration. Digital signal tests do not establish listening quality or hardware safety.

## Launch Services checks (opt-in)

`bash scripts/test-launch.sh` launches an isolated test bundle through macOS Launch Services and observes its window for five seconds without a UI automation client activating or reopening it. It checks first launch, a subsequent launch, and a simulated login launch. Preferences are isolated and audio restoration is disabled. Run it in a desktop session after building the app.

## Screenshots

`bash scripts/screenshots.sh` renders the real SwiftUI views into PNGs with isolated demo preferences and no audio capture. The images show demo routing, a Bass Boost curve, and startup options off. They contain no user app inventory. Review the output before committing.
