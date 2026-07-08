# TimePass — Progress

**Updated:** 2026-07-08 (evening) · living document, newest state first.
Companion docs: `PRODUCT_SPEC.md` (what & why) · `COMPONENT_CATALOG.md` (UI contract) · `README.md` (how to run).

## Where we are, in one paragraph

The M0 vertical slice is **built, tested, and running on a real phone** (Samsung Galaxy S23 FE over wireless adb): ask anything in en/hi/te → a generated interactive interface renders in the Flutter app from an A2UI stream. Hero answers (cricket/panchang/weather/AQI) are deterministic server templates; the generic tier is **live on Gemini Flash-Lite** and streams progressively. **AQI is the first hero category on real data** (CPCB via data.gov.in, all-India stations, localized). Remaining M0 gaps: cricket/panchang/weather adapters still serve fixtures, and generic-tier tail latency (p90 ~12s) is above target.

## Scoreboard (measured, not vibes)

| Metric | Value | How measured |
|---|---|---|
| Generic-tier validity | **27/30 (90%)**, 0 hard errors | `server/evals/run_evals.py`, 30 diverse queries en/hi/te |
| First visual response | **~0.4s** (placeholder skeleton) | streamed message timestamps |
| Caption (TTS line) | **p50 1.6s** / p90 9s | eval harness |
| Full validated surface | **p50 5.1s** / p90 12.2s | eval harness |
| Hero answers (cached path) | instant (<0.5s) | template + adapter, no LLM |
| Residual failures | mostly Google free-tier 503s | server logs |
| Tests | 28 server + 5 Flutter renderer, all green | `uv run pytest` / `flutter test` |

Component adoption across the eval set: Checklist ×10, ComparisonTable ×5 — the model picks the new components for exactly the query shapes they were built for.

## What's built (by layer)

**Catalog (`catalog/`)** — single source of truth `catalog.yaml` → generator emits `catalog.json` (validation schema), `system_prompt.md` (LLM prompt fragment), `schemas.g.dart` (Flutter). 19 components live: 10 Basic-Catalog primitives + Markdown, KeyValueGrid, ComparisonTable, Checklist, Notice, FollowUpChips, CricketLiveScore, PanchangCard, WeatherStrip, AqiMeter. Contract for the remaining 16 (incl. all monetization components) frozen in `COMPONENT_CATALOG.md`.

**Server (`server/`)** — FastAPI orchestrator: keyword intent router (M0 stub) → hero templates with data-model bindings OR streaming Gemini generic tier → **fail-closed catalog validator** (nothing off-catalog ever ships) → A2UI v0.9-wire NDJSON. Robustness stack for LLM output: shape normalizer (nested→flat, cells variants, prop pruning, lenient JSON) + validation-feedback retry + 503 backoff. Eval harness in `server/evals/`.

**App (`app/`)** — Flutter + genui 0.9.2. One `CatalogItem` per component (plain M0 styling by design — the polish pass comes per the plan), `{path}` bindings resolve reactively, follow-up chips and checklist toggles round-trip as typed events. Renderer contract tests replay real recorded server streams.

## Integrations & keys

| Integration | Status | Notes |
|---|---|---|
| Gemini (generic tier) | ✅ live | `gemini-2.5-flash-lite`; key in SSM `/shared/gemini-api-key` (**rotate at some point** — passed through chat once). Free tier throws 503s under load; paid tier likely needed at launch. |
| CPCB AQI (data.gov.in) | ✅ live | Key in SSM `/shared/datagovin-api-key`. All-India stations, per-city rollup (mean of station AQIs, dominant pollutant), 10-min cache, fixture fallback. |
| IMD weather | ⏳ pending | Profile submitted on api.imd.gov.in as Private/Profit "ritivel" — awaiting IMD approval. Adapter still fixture. |
| Cricket feed | ☐ decision | EntitySport (~$150/mo) vs Roanuz — commercial call, fixtures until then. |
| Panchang (Prokerala) | ☐ signup | Free tier exists; adapter still fixture. |
| Sarvam (ASR/TTS) | ☐ M1 | Voice in + spoken caption. |
| DPIIT / TIES / TMDB | ☐ paper track | Slow-moving; start early (spec §10). |

## Hard-won facts (don't relearn these)

- **genui 0.9.2 requires wire `"version": "v0.9"`** — rejects `"v0.9.1"` (patch releases share the wire version).
- **genui's Basic Catalog has no Markdown component** (its `Text` renders markdown); we ship our own.
- `CatalogItem.dataSchema` must exclude `id`/`component` (injected); renderer matches surfaces to catalogs by **exact catalogId string**.
- **Flash-Lite: setting `thinking_config` (even budget 0) adds ~4s TTFT.** Leave defaults.
- The single biggest latency/cost lever is **prompting for compact composition** (3–6 components) — cut a 24s worst case to 5s.
- LLMs make recurring wire-format mistakes (nested children, keyed cells, hallucinated props, literal newlines in JSON) — **normalize deterministically, then validate strictly**; retry with validation errors as feedback rescues most of the rest.
- **data.gov.in's WAF tarpits the default python UA** (requests hang to timeout); any explicit User-Agent goes through in ~1s. Gov endpoints also drop occasional TLS handshakes — retry once.
- USB-C cables are usually charge-only; **wireless debugging** (pair → mDNS auto-connect) is the reliable path to the user's S23 FE. `adb reverse tcp:8000 tcp:8000` bridges app→laptop.

## Next steps (priority order)

1. **Rebuild the phone app** — the installed build predates ComparisonTable/Checklist and the streaming client.
2. **IMD weather adapter** when approval lands (adapter seam + fallback pattern already proven with AQI).
3. **Panchang real adapter** — Prokerala free tier + per-city/day cache.
4. **Generic-tier tail latency** — p90 is 503-retry dominated; evaluate paid Gemini tier vs request hedging; consider streaming components before the final validation for trusted subsets.
5. **Cricket feed decision** (EntitySport trial recommended), then the live-refresh loop (`updateDataModel` push on a timer, shared per match).
6. **M1**: Sarvam voice in + TTS caption; real intent router; then the **design pass** on the catalog (layer 3 of the agreed plan).

## Milestone tracker (spec §9)

- **M0 (weeks 1–3)**: app + renderer + 8 components ✅ · hi/en/te input ✅ · te output ✅ · <4s answers ✅ hero / ⚠ generic (p50 5.1s) · "real APIs" ⚠ 1 of 3 (AQI live; cricket+panchang+weather fixtures)
- **M1 (weeks 4–8)**: not started — voice, 6 hero categories, 100-user beta
- **M2 (weeks 9–14)**: not started — monetization components, TIES filing, legal opinions
