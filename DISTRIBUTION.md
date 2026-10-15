# Runway distribution

## Current preview

The current version is preview software. It is currently ad-hoc signed, not signed with
an Apple Developer ID, and not notarized by Apple. macOS may require Control-click,
then **Open**. The DMG contains only the app and an Applications shortcut.

## Local package

Run:

```sh
./scripts/package_release.sh
```

This creates an anonymous, ad-hoc signed ZIP and DMG. Identified Apple signing and
notarization are unsupported by the preview packaging policy; requesting either
fails before any build or cleanup. Use `HEADLESS_PACKAGE=1` to package without
mounting the DMG or driving Finder.

## Sparkle updates

Sparkle 2.9.4 is configured to check daily and automatically install updates. The
app also provides **Runway > Check for Updates…**. Update archives and
the appcast are signed with the existing Sparkle EdDSA key; the app verifies both
the signed feed and archive before extraction.

Ad-hoc previews can update through Sparkle because the archive and feed use its
EdDSA signatures. The preview packages retain anonymous Apple signing and may
still show Gatekeeper warnings.

The Sparkle private key is stored in the developer login Keychain. Keep a secure
backup: future updates must use the same key unless a supported key rotation is
performed.

## Publish a release

Authenticate `gh`, then run:

```sh
./scripts/publish_github_release.sh
```

The script derives the version from the built app, generates and validates the
Sparkle-signed appcast, and uploads the ZIP, DMG, appcast, and checksums. Public
preview packages follow the same anonymous ad-hoc signing policy.
