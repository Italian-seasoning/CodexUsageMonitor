# Codex Usage Monitor distribution

## Current preview

Version 2.0.1 is preview software. It is currently ad-hoc signed, not signed with
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

Unsigned previews can update through Sparkle because the archive and feed use its
EdDSA signatures. Apple Developer ID signing is still required to avoid Gatekeeper
warnings and provide a stable macOS identity for permissions and widgets.

The Sparkle private key is stored in the developer login Keychain. Keep a secure
backup: future updates must use the same key unless a supported key rotation is
performed.

## Publish a release

Authenticate `gh`, then run:

```sh
./scripts/publish_github_release.sh 2.0.1
```

The script derives the version from the built app, generates and validates the
Sparkle-signed appcast, and uploads the ZIP, DMG, appcast, and checksums. Set
`SIGN_IDENTITY` and `NOTARY_PROFILE` when Developer ID credentials are available.
