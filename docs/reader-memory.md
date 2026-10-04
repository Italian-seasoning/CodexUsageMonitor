# Reader memory check

Version 3.1.4 replaces whole-file transcript and Headroom ledger reads with
64 KiB streaming reads. Each decoded row has its own autorelease pool, and each
snapshot has a pool for temporary Foundation cache and aggregation objects.
Usage samples, lineage and rate limits remain available for the existing totals.
Memory still depends on the largest individual row and retained usage samples.

A local optimized reader harness processed a synthetic 128 MiB transcript three
times: cold, cached, then cold again. Before the change, resident memory was
437, 437 and 604 MiB. After the change it was 11, 11 and 12 MiB. All three reads
returned the expected token and turn totals. These are reader-process figures,
not a promise about the full application's memory on another Mac. The reported
2 GB process on the affected Mac has not been profiled directly.

The fixed harness also read a 512 MiB synthetic transcript three times at about
10 MiB resident memory. On roughly 3 GiB of local session logs, cold and cached
refreshes ended at 148 and 155 MiB resident, with a 218 MiB peak. That live history
was being updated during the check. The full app includes UI and other services.

Build and run from the repository root:

```sh
rtk proxy swiftc -O Shared/CodexUsageSnapshot.swift Shared/CodexUsageSettings.swift Shared/WidgetConfiguration.swift Shared/UsageMetrics.swift scripts/ReaderMemoryCheck.swift -o /tmp/codex-reader-memory
rtk proxy /usr/bin/time -l /tmp/codex-reader-memory 128
```

Use `--live` instead of `128` to read local session logs with a temporary reader
cache. The harness prints aggregate counts and memory, never transcript content.
It removes only its own temporary fixtures and cache after completion.
