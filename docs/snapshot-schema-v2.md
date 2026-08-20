# Codex Usage Snapshot V2

Codex Usage Monitor writes one local JSON snapshot for the macOS app, menu bar, refresh helper, and WidgetKit extension. This document defines the platform-neutral data contract for a possible future Windows reader. It does not define a cross-platform runtime.

## Contract

- Dates are ISO-8601 instants when represented outside Swift's native `Codable` transport.
- Token and count fields are integers.
- Currency fields ending in `USD` are US dollars; `estimatedCostMicros` is millionths of one US dollar.
- API-equivalent estimates apply the recorded model's public uncached-input, cached-input, output, and long-context rates. They are not subscription spending.
- `today` uses the reader's local calendar day. `sevenDays` includes today plus the preceding six calendar days. `month` starts at the local calendar month's first day. `lifetime` includes every valid record up to `generatedAt`.
- Records dated after the evaluation time are excluded from period summaries.
- Unknown models remain in token totals. Their cost is excluded and their tokens are added to `unpricedTokens`.
- Optional fields may be absent in V1 snapshots. Readers must preserve valid fields when another optional source is unavailable.

## Freshness

`generatedAt` is the snapshot creation time and is the primary freshness clock.

- Fresh: age is at most 10 minutes.
- Stale: a valid snapshot exists but is older than 10 minutes.
- Partial: primary usage is valid but one or more optional model, limit, or Headroom sources are missing.
- Unavailable: no valid usage source was found.
- Permission blocked and refresh errors are stored in the separate background refresh status record, not inferred from zero usage.

Widget timelines request a new shared snapshot every three minutes. WidgetKit may delay the visible redraw after a reload request.

## Root fields

| Field | Type | Unit | Optional | Meaning |
| --- | --- | --- | --- | --- |
| `currentSession` | `TokenUsage` | tokens | no | Current session aggregate |
| `lifetime` | `TokenUsage` | tokens | no | All valid recorded usage |
| `today` | `TokenUsage` | tokens | no | Current local calendar day |
| `peakDay` | `DailyUsage` | mixed | yes | Highest recorded daily token total |
| `currentStreak` | integer | days | no | Consecutive activity days ending at the latest activity day |
| `longestStreak` | integer | days | no | Longest recorded activity streak |
| `lastUpdated` | date | instant | yes | Latest source event time |
| `activityDays` | array of `DailyUsage` | mixed | no | Dated daily aggregates |
| `generatedAt` | date | instant | yes | Snapshot write time and freshness origin |
| `sessionCount` | integer | sessions | yes | Lifetime session count |
| `turnCount` | integer | requests | yes | Lifetime request/turn count |
| `currentSessionTurns` | integer | requests | yes | Current session request/turn count |
| `currentSessionStartedAt` | date | instant | yes | Current session start |
| `currentContextTokens` | integer | tokens | yes | Current context occupancy |
| `contextWindow` | integer | tokens | yes | Current model context capacity |
| `headroom` | `HeadroomSavings` | mixed | yes | Local Headroom compression metrics |
| `modelUsage` | array of `ModelUsage` | mixed | yes | Legacy lifetime model aggregates |
| `dailyModelUsage` | array of `DailyModelUsage` | mixed | no | Dated model aggregates used by V2 periods |
| `topModelToday` | string | model ID | yes | Cached top-model label |
| `topModelLast7Days` | string | model ID | yes | Cached top-model label |
| `topModelThisMonth` | string | model ID | yes | Cached top-model label |
| `topModelLifetime` | string | model ID | yes | Cached top-model label |
| `currentModel` | string | model ID | yes | Current session model; never substitutes for a token metric |
| `unpricedTokens` | integer | tokens | yes | Usage without a matching public model rate |
| `pricingVersion` | string | version | yes | Pricing catalog identifier |
| `rateLimits` | `CodexRateLimits` | mixed | yes | Current limit windows and history |

## Nested records

### `TokenUsage`

`input`, `cachedInput`, `output`, `reasoningOutput`, and `total` are integer token counts. `total` is the source's complete total and is not recomputed by consumers.

### `DailyUsage`

| Field | Type | Unit | Optional |
| --- | --- | --- | --- |
| `date` | date | local calendar day | no |
| `usage` | `TokenUsage` | tokens | no |
| `sessions` | integer | sessions | no |
| `turns` | integer | requests | yes |
| `headroomSaved` | integer | tokens | yes |
| `estimatedCostMicros` | integer | millionths USD | yes |

### `ModelUsage`

`model` is the recorded model ID, `usage` is `TokenUsage`, `turns` is a request count, and `estimatedCostUSD` is the model-aware API-equivalent estimate.

### `DailyModelUsage`

`date` is the local calendar day and `models` is that day's complete array of `ModelUsage` records.

### `HeadroomSavings`

Token fields are `lifetimeTokensSaved`, `todayTokensSaved`, and `last7DaysTokensSaved`. Request fields are `lifetimeRequests` and `todayRequests`. `inputTokensBeforeCompression` is the original input-token count, `savingsPercent` is a 0...1 ratio, and `costSavedUSD`/`todayCostSavedUSD` are API-equivalent estimates. `lastUpdated` and `trackingStartedAt` are optional instants. `topModel` and `schemaVersion` are optional source metadata.

### `CodexRateLimits`

`fiveHour` and `weekly` are optional `RateLimitWindow` values. Each window stores `usedPercent` as 0...100, `windowMinutes`, `resetsAt`, and `observedAt`. UI hero values show `100 - usedPercent`, clamped to 0...100, as remaining allowance.

`history` contains `RateLimitHistoryPoint` records with `date`, optional `fiveHourUsedPercent`, and optional `weeklyUsedPercent`.

## Sanitized example

```json
{
  "currentSession": {"input": 800, "cachedInput": 100, "output": 90, "reasoningOutput": 10, "total": 1000},
  "lifetime": {"input": 9000, "cachedInput": 1000, "output": 900, "reasoningOutput": 100, "total": 11000},
  "today": {"input": 800, "cachedInput": 100, "output": 90, "reasoningOutput": 10, "total": 1000},
  "peakDay": null,
  "currentStreak": 1,
  "longestStreak": 4,
  "lastUpdated": "2026-07-24T13:00:00Z",
  "activityDays": [{
    "date": "2026-07-24T07:00:00Z",
    "usage": {"input": 800, "cachedInput": 100, "output": 90, "reasoningOutput": 10, "total": 1000},
    "sessions": 1,
    "turns": 8,
    "headroomSaved": 240,
    "estimatedCostMicros": 6200
  }],
  "generatedAt": "2026-07-24T13:00:00Z",
  "sessionCount": 6,
  "turnCount": 42,
  "currentSessionTurns": 8,
  "currentSessionStartedAt": "2026-07-24T12:40:00Z",
  "currentContextTokens": 32000,
  "contextWindow": 272000,
  "headroom": {
    "lifetimeTokensSaved": 2000,
    "todayTokensSaved": 240,
    "last7DaysTokensSaved": 900,
    "lifetimeRequests": 40,
    "todayRequests": 8,
    "inputTokensBeforeCompression": 13000,
    "savingsPercent": 0.15,
    "costSavedUSD": 0.03,
    "todayCostSavedUSD": 0.004,
    "lastUpdated": "2026-07-24T13:00:00Z"
  },
  "modelUsage": [],
  "dailyModelUsage": [{
    "date": "2026-07-24T07:00:00Z",
    "models": [{
      "model": "gpt-example",
      "usage": {"input": 800, "cachedInput": 100, "output": 90, "reasoningOutput": 10, "total": 1000},
      "turns": 8,
      "estimatedCostUSD": 0.0062
    }]
  }],
  "topModelToday": "gpt-example",
  "topModelLast7Days": "gpt-example",
  "topModelThisMonth": "gpt-example",
  "topModelLifetime": "gpt-example",
  "currentModel": "gpt-example",
  "unpricedTokens": 0,
  "pricingVersion": "example-2026-07",
  "rateLimits": {
    "fiveHour": {"usedPercent": 25, "windowMinutes": 300, "resetsAt": "2026-07-24T15:00:00Z", "observedAt": "2026-07-24T13:00:00Z"},
    "weekly": {"usedPercent": 40, "windowMinutes": 10080, "resetsAt": "2026-07-28T07:00:00Z", "observedAt": "2026-07-24T13:00:00Z"},
    "history": []
  }
}
```
