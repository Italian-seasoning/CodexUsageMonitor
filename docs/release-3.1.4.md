# Codex Usage Monitor 3.1.4 preview

Reduces memory spikes during refreshes of large Codex histories. Session and
Headroom logs are streamed in 64 KiB reads, and temporary Foundation objects
are released after each JSON row and refresh.

Adds GPT-6.1 Sol usage and API-equivalent cost estimates, including cached input,
long-context rates and dated model IDs. Existing histories are repriced on refresh.

Validation: 51 Xcode tests passed, including parameterized streaming and pricing
checks; the session reader's 10 deterministic scenarios and Headroom collector
check passed. An optimized 128 MiB synthetic reader check fell from a 604 MiB
peak to about 12 MiB across cold/cached/cold reads, with identical totals. A live
reader check against roughly 3 GiB of session logs peaked at about 218 MiB.
These measurements cover the reader, not the entire app on every Mac.

This preview is ad-hoc signed and Sparkle-signed for automatic updates. It is
not Apple Developer ID signed or notarized. macOS may require Control-click,
then Open on a fresh installation.
