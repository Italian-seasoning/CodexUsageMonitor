#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: verify_release_privacy.sh /path/to/App.app}"
[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 2; }

if find "$APP" -name embedded.provisionprofile -print -quit | grep -q .; then
  echo "Privacy check failed: embedded provisioning profile found." >&2
  exit 1
fi

private_files="$(
  find "$APP" -type f -print0 \
    | xargs -0 grep -alE '/Users/[^/[:space:]]+/|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' \
    || true
)"
if [[ -n "$private_files" ]]; then
  echo "Privacy check failed: local home path or email address found in app bundle." >&2
  exit 1
fi

signature_info="$(codesign -dvvv "$APP" 2>&1 || true)"
if grep -q '^Authority=' <<<"$signature_info"; then
  echo "Privacy check failed: public build contains an identified signing certificate." >&2
  exit 1
fi
if ! grep -q '^TeamIdentifier=not set$' <<<"$signature_info"; then
  echo "Privacy check failed: public build contains a signing team identifier." >&2
  exit 1
fi

echo "Release privacy check passed."
