# Changelog

## 0.4.0 — preview 4 · 2026-10-15

- Display name is now eqMini. Bundle identity and saved preferences are unchanged.
- One three-fader mark across the app icon, header, About, and monochrome menu-bar icon.
- Normal launches open the menu-bar panel. A regular window is available from the menu; login launches stay quiet.
- Enable/Disable wording replaces Enable/Bypass.
- The window explains that closing it keeps eqMini running in the menu bar.

## 0.4.0 — preview 3 · 2026-10-15

- Right-click the menu-bar icon for quick actions; left-click still opens the panel.
- Normal launches open the equalizer window. Login launches remain quiet.
- The first enable after an update shows the audio explanation from every enable control, including the window menu.
- Paused sources no longer fail the callback watchdog. Recovery requires a sustained stall during confirmed playback on the current output.
- Audio Recording Settings is offered for permission failures rather than every audio error.

## 0.4.0 — preview 2 · 2026-10-15

- Developer ID signing with hardened runtime and the Core Audio input entitlement.
- Apple notarization and stapled tickets for the app and DMG; both pass local Gatekeeper assessment.
- Build number 6. Audio processing and controls are unchanged.

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
