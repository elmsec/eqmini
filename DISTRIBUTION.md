# Distribution

## Current preview

Version **0.4.0 preview 1** is built for **Apple silicon** and macOS **14.2+**. ZIP and drag-to-Applications DMG assets are provided with SHA-256 checksums. They are **ad-hoc signed, not Developer ID signed or notarized**. They may be blocked when downloaded. This is an explicit preview limitation, not a clean-Mac installation guarantee.

If a user chooses to run a trusted preview, Apple's per-app Open Anyway flow is available in Privacy & Security. Never recommend disabling Gatekeeper or stripping quarantine globally. Building from source is another option.

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

## References

- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: opening downloaded apps](https://support.apple.com/en-us/102445)
- [Apple: Developer ID](https://developer.apple.com/developer-id/)
