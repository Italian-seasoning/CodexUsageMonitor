# Codex Usage Monitor for macOS

Drag `CodexUsageMonitor.app` to Applications, then open it. The first-run tour explains the live local totals, model-aware API estimate, Headroom units, and widget settings.

The app installs its bundled 60-second refresh helper as a user LaunchAgent when first opened. No administrator password is required. Usage data stays on the Mac and is read from the current user's local Codex session logs.

## Gatekeeper

This build is ad-hoc signed unless the packager has a Developer ID Application certificate. For an ad-hoc build, macOS may require Control-clicking the app and choosing Open. A normal double-click experience requires Developer ID signing and Apple notarization.

## Building a notarized release

Set `SIGN_IDENTITY` to a Developer ID Application identity and `NOTARY_PROFILE` to a configured `notarytool` keychain profile, then run:

```bash
./scripts/package_release.sh
```
# Automatic updates

Codex Usage Monitor uses Sparkle 2 and GitHub Releases. It checks once per day,
downloads updates automatically, and asks before installing them. Users can also
choose **Codex Usage Monitor > Check for Updates…**.

The Sparkle private EdDSA key is stored in the developer login Keychain. The app
contains only its public key. Do not delete the private key, because future update
archives must be signed by the same key.

To publish version 1.1.2 after configuring a Developer ID certificate,
notarization profile, GitHub repository, and `gh auth login`:

```sh
SIGN_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="codex-usage-notary" \
./scripts/publish_github_release.sh 1.1.2
```

The script packages and notarizes the app, generates a Sparkle-signed appcast,
and uploads the ZIP, DMG, checksums, and `appcast.xml` to GitHub Release `v1.1.2`.

