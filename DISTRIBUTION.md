# Codex Usage Monitor distribution

## Current preview

Version 1.1.2 is preview software. It is currently ad-hoc signed, not signed with
an Apple Developer ID, and not notarized by Apple. macOS may require Control-click,
then **Open**. The DMG contains only the app and an Applications shortcut.

## Local package

Run:

```sh
./scripts/package_release.sh
```

Without a Developer ID certificate this creates an ad-hoc signed ZIP and DMG for
local testing. With `SIGN_IDENTITY` and `NOTARY_PROFILE`, it signs, notarizes, and
staples the DMG.

## Sparkle updates

Sparkle 2.9.4 is configured to check daily and automatically install updates. The
app also provides **Codex Usage Monitor > Check for Updates…**. Update archives and
the appcast are signed with the existing Sparkle EdDSA key; the app verifies both
the signed feed and archive before extraction.

The updater becomes operational after the first Developer ID signed, notarized
GitHub Release publishes `appcast.xml`. The unsigned preview is intentionally not
published as a production update.

The Sparkle private key is stored in the developer login Keychain. Keep a secure
backup: future updates must use the same key unless a supported key rotation is
performed.

## Publish a production release

Install a Developer ID Application certificate, configure a `notarytool` Keychain
profile, authenticate `gh`, then run:

```sh
SIGN_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="codex-usage-notary" \
./scripts/publish_github_release.sh 1.1.2
```

The script refuses unsigned publication, derives the version from the built app,
generates and validates the signed appcast, and uploads the ZIP, DMG, appcast, and
checksums to GitHub Release `v1.1.2`.
