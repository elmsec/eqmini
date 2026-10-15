# Architecture

## App and settings

`EqminiApp.swift` owns the process entry point. `AppDelegate.swift` owns the status item, popover, regular windows, and macOS menus. Both equalizer surfaces observe the same `EqualizerModel`; opening another surface does not create another audio engine.

`EqualizerModel.swift` owns UI state, preference validation/migration, app selection, and route lifecycle. `EqualizerView.swift` contains the panel and faders. `AppViews.swift` and `SettingsView.swift` contain the window, About, and Settings content. `StartupSettings.swift` wraps `SMAppService` behind a small testable interface. Login status comes from macOS, not a duplicate preference.

The stable bundle identifier is `dev.elma.eqmini`. On the first normal launch, known settings are copied from the prototype's `local.mac-equalizer.app` preferences only where the new preferences have no value. Migration is marked complete and does not repeat. Audio permission belongs to the new app identity and may need to be granted again.

Simple mode fits three broad frequency-weight profiles to the ten-band curve, rounding the displayed controls to half-decibel steps. The remaining per-band residual is saved separately. Changing views never reconstructs or changes the active curve. Adjusting a Simple control adds its broad profile to that residual and clamps the resulting bands to ±12 dB.

## Audio control

All route creation/destruction and process enumeration run on `eqmini.audio-control`. UI state is updated on the main queue. A generation counter rejects results from a superseded enable/reconfigure request. Main-thread code clears `routeActive` before queueing teardown, so polling does not inspect a route being destroyed.

`AudioBridge.h` is the narrow C interface used by Swift. `AudioEngine.mm` owns a single DSP instance, process tap, aggregate device, and HAL I/O callback. Engine lifecycle calls must be serialized by their caller. Atomic parameter setters and metering are safe across the UI/control and audio threads.

The tap is private and specific to the default output. All-audio mode excludes this process. Selected-app mode includes only selected process IDs, excluding this process even if passed explicitly. The aggregate includes the physical output and tap, with tap drift compensation. Hardware input streams are disabled. The app does not set the system's default output device.

Tap muting applies only while capture is active. Stop releases the I/O procedure, aggregate, and tap. Failed setup tears down partial resources. Device checks handle route changes. A callback watchdog releases a stalled route only after sustained missing callbacks during confirmed source playback on the current output. Paused sources and unknown or stale playback inventories reset the grace period. Device/rate changes and wake events schedule a rebuild.

## Render path

1. Clear output buffers and bound the frame count by all participating channel buffers.
2. Snapshot/smooth atomic gain targets for the block.
3. Apply the preamp and ten peaking biquads independently to left and right.
4. Mix the optional parallel bass-harmonic signal.
5. Apply a linked stereo sample-peak limiter and startup fade.

The callback does not allocate, lock, log, access files, or call Objective-C. Filter state belongs to the audio thread. Parameters and meters use atomics. The limiter is not oversampled and does not guarantee intersample true-peak bounds.

With Keep volume off, a response scan estimates the EQ's largest boost and attenuates the input accordingly. Keep volume removes that attenuation; Output is an additional independent gain. The limiter remains active in both cases. This is gain compensation, not perceptual loudness normalization.

## Trust boundaries

Audio buffers stay in memory. Only preferences and app selections are persisted. There is no app networking, telemetry, updater, recording feature, driver, privileged helper, or separate background service. Links open the browser, where the destination's policies apply. Diagnostic commands are explicit and may print app/process metadata.

`AudioDiagnostics.swift` contains opt-in hardware checks. Pure settings/login-service fakes live under `Tests/` and are excluded from the shipped executable. Documentation images are rendered from actual SwiftUI views with isolated demo preferences, not the user's running-app list.

Normal launches open the equalizer window; login launches stay in the menu bar. A per-build acknowledgement gates every enable entry point before capture starts. Login restoration waits for acknowledgement from a visible launch after an update.
