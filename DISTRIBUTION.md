# Distribution

## Current preview

Version **0.4.0 preview 5** (build 9) is built for **Apple silicon** and macOS **14.2+**. ZIP and drag-to-Applications DMG assets are provided with SHA-256 checksums. The app and DMG are **Developer ID signed and notarized by Apple**, with stapled tickets. Both pass local Gatekeeper assessment as `Notarized Developer ID`.

Preview 1 was ad-hoc signed; use a current release for a notarized download.

## Packaging

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh --preview
```

Packaging stages a copy of the built app; it does not modify a running installation. Preview names include `preview`, and the DMG includes a notice. The package script refuses a standard release without explicit Developer ID and notarization configuration.

For a distribution release, import your **Developer ID Application** certificate into your login keychain and store notarization credentials using Apple's `notarytool store-credentials`. Keep credentials outside the repository.

```sh
export CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='your-keychain-profile'
bash scripts/package.sh
```

The script signs with hardened runtime and a secure timestamp, notarizes/staples the app, creates ZIP/DMG packages, notarizes/staples the DMG, and writes checksums. It stops on any signing, submission, or stapling failure. No signing identity or credentials are embedded in source or CI. Current CI builds and tests only; release publication is manual.

`Eqmini.entitlements` enables hardened runtime Audio Input access for Core Audio. The app does not read the microphone or enable hardware input. No other hardened runtime exceptions are requested.

## References

- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: opening downloaded apps](https://support.apple.com/en-us/102445)
- [Apple: Developer ID](https://developer.apple.com/developer-id/)
