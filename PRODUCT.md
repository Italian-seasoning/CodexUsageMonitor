# Product

## Register

product

## Users

Nolan uses this on macOS while working in Codex. The job is to glance at current-session and local lifetime usage without opening logs or a browser.

## Product Purpose

Codex Usage Monitor reads local Codex session logs and presents current session, lifetime, peak day, streak, and recent activity in a native app and WidgetKit widget.

## Brand Personality

Precise, compact, technical. The interface should feel like a sharp local instrument, not a dashboard demo.

## Anti-references

Avoid SaaS dashboard gradients, decorative glassmorphism, vague neon palettes, oversized cards, and marketing-page composition.

## Design Principles

- Show the profile-card stats first.
- Keep the widget compact enough for repeated glances.
- Use local data honestly and label it as local when needed.
- Prefer native macOS and WidgetKit behavior over custom machinery.
- The helper app uses a focused dark palette: coral red `#FF6363`, near-black `#101010`, and white `#FEFEFE`.
- Use red for selection, status, and primary actions. Keep passive data surfaces calm and nearly monochrome.
- First run opens with a concise welcome and a four-step spotlight tour over the real interface. The tour remains replayable from Help.
- Refresh and Apply use cursor-following red glow borders as pointer affordances. Passive panels never glow.
- Widget surfaces stay restrained and instrument-like while respecting WidgetKit monochrome and tinted rendering.
- Label graph scaling explicitly: each chart is normalized to the largest visible day, shown as its peak value rather than an unexplained percentage.
- Present model-aware cost as an API-equivalent estimate, never as actual ChatGPT subscription spending.

## Accessibility & Inclusion

Target readable contrast in light and dark appearances. Preserve WidgetKit monochrome and tinted rendering with luminance differences instead of hue-only meaning.
