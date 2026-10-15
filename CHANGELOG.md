# Changelog

## 0.4.0 — preview 1 · 2026-10-15

First packaged preview. Apple silicon, macOS 14.2+; ad-hoc signed, not notarized.

- System-wide or selected-app EQ through a private Core Audio process tap.
- Ten bands, Flat/Bass Boost/Warm presets, saved Custom curve, and reset controls.
- Simple Bass/Voices/Detail controls that follow the existing curve without changing it when switching views.
- Speaker bass harmonics, full headroom compensation, independent output gain, and linked stereo peak protection.
- Menu bar panel, resizable equalizer window, native menus, About, and Settings.
- Opt-in launch at login and restore-on-launch, with quiet login launches and approval status.
- Stable `dev.elma.eqmini` identity and migration from prototype preferences. The identity change may require a new audio permission grant.
- Separate source modules, isolated model/startup tests, DSP sanitizer coverage, CI, and documented release tooling.

Known release limits are documented in the README and distribution guide. No automatic update mechanism is included.
