# TimePass — Progress

**Updated:** 2026-07-08 (night) · living document, newest state first.
Companion docs: `PRODUCT_SPEC.md` (what & why) · `COMPONENT_CATALOG.md` (UI contract) · `README.md` (how to run).

## Where we are, in one paragraph

The M0 vertical slice is **built, tested, and running on a real phone** (Samsung Galaxy S23 FE over wireless adb), and the generic tier is now genuinely ChatGPT-class in shape: **search-grounded answers with source attribution** for time-sensitive queries, **multi-turn conversation context**, and **live-updating surfaces** (cricket card refreshes ball-by-ball over a push stream — fixture-fed until a real feed lands). AQI serves real CPCB data. The LLM sits behind a **provider interface** (Gemini today; OpenAI/Anthropic pluggable). The app persists conversations across restarts and recovers from errors. Remaining M0 gaps: cricket/panchang/weather adapters still serve fixtures; grounded-query latency (~15–18s) is the slowest path.

## Scoreboard (measured, not vibes)

| Metric | Value | How measured |
|---|---|---|
| Generic-tier validity | **29/30 (97%)**, 0 hard errors | `server/evals/run_evals.py`, 30 diverse queries en/hi/te |
| First visual response | **~0.4s** (placeholder skeleton) | streamed message timestamps |
| Caption (TTS line) | **p50 1.25s** / p90 4.2s | eval harness |
| Full validated surface | **p50 5.0s** / p90 8.5s | eval harness |
| Grounded (search) queries | ~15–18s end-to-end; gated to time-sensitive queries only | live tests |
| Hero answers (cached path) | instant (<0.5s); cricket refreshes every 8s while live | template + adapter, no LLM |
| Tests | 34 server + 5 Flutter renderer, all green | `uv run pytest` / `flutter test` |

Grounding-gate history (same 30-query set): always-ground → 26/30 valid, caption p50 **14.4s**, 70–77% of queries searched; prompt-only discipline → no improvement; **server-side freshness gate → 29/30, caption p50 1.25s, 1/30 searched**. The model will not self-limit search; the server must decide.

## What's built (by layer)

**Catalog (`catalog/`)** — single source of truth `catalog.yaml` → generator emits `catalog.json` (validation schema), `system_prompt.md` (LLM prompt fragment), `schemas.g.dart` (Flutter). 19 components live: 10 Basic-Catalog primitives + Markdown, KeyValueGrid, ComparisonTable, Checklist, Notice, FollowUpChips, CricketLiveScore, PanchangCard, WeatherStrip, AqiMeter. Contract for the remaining 16 (incl. all monetization components) frozen in `COMPONENT_CATALOG.md`.

**Server (`server/`)** — FastAPI orchestrator: keyword intent router (M0 stub) → hero templates with data-model bindings OR streaming generic tier → **fail-closed catalog validator** (nothing off-catalog ever ships) → A2UI v0.9-wire NDJSON. The generic tier lives behind a **provider interface** (`llm/base.py`; Gemini in `llm/gemini.py`, selected by `LLM_PROVIDER`): freshness-gated search grounding (grounded plain-text answer → strict-JSON compose pass; sources → server-built SourceChips), client-supplied conversation history (stateless server), shape normalizer + validation-feedback retry + 503 backoff. **Live surfaces**: `GET /v1/live/{surface_id}` pushes `updateDataModel` refreshes until TTL (cricket: every 8s). Eval harness in `server/evals/`.

**App (`app/`)** — Flutter + genui 0.9.2. One `CatalogItem` per component (plain M0 styling by design — the polish pass comes per the plan), `{path}` bindings resolve reactively, follow-up chips / checklist toggles / source taps round-trip as typed events. Conversations persist across restarts (raw NDJSON replay via shared_preferences), live surfaces show a LIVE badge and auto-update, errors get a friendly retry card. Renderer contract tests replay real recorded server streams.

## Integrations & keys

| Integration | Status | Notes |
|---|---|---|
| Gemini (generic tier) | ✅ live, **paid tier** | `gemini-2.5-flash-lite`; key in SSM `/shared/gemini-api-key` (**rotate at some point** — passed through chat). Paid tier verified 2026-07-08: zero 429s at 10-parallel burst. Note: `503 UNAVAILABLE` ("high demand") is Google-side *capacity*, not rate limiting — no tier eliminates it; eval scores swing ±10% run-to-run with it. Mitigation candidate: retry-on-503 via `gemini-2.5-flash` (separate capacity pool, failures-only cost). |
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
- **Gemini search grounding is incompatible with JSON mode** (`google_search` tool + `response_mime_type` → error), and when the model does search it **drops the JSON contract entirely** and answers in plain text — hence the two-phase grounded flow (search → strict-JSON compose).
- **Prompt instructions cannot discipline tool use on Flash-Lite**: with `google_search` available it searched 70–77% of queries no matter what the system prompt said. Gate server-side.
- Grounding costs money at scale (1,500 free grounded prompts/day, then ~$14/1k) — another reason the freshness gate is server-owned.

## Roadmap

### Near term (unblocks M0 completion)

1. ~~Rebuild the phone app~~ — done 2026-07-08: release APK built against the laptop's LAN IP (`--dart-define=TIMEPASS_API=http://192.168.1.2:8000`, server on `--host 0.0.0.0`), so the app runs standalone over Wi-Fi with no adb bridge.
2. **Real adapters for the remaining hero fixtures**:
   - *Weather* — blocked on IMD approval (profile submitted); seam + fallback pattern proven with AQI.
   - *Panchang* — needs a Prokerala signup (user, free tier); then per-city/day caching makes it ~₹0.
   - *Cricket* — commercial decision (EntitySport trial ~$150/mo recommended); the live-refresh pipeline is built and waiting — the real feed replaces `_snapshots()` in the adapter.
3. **Freshness-gate refinement** — known miss: "jio vs airtel plans under 300" (current prices, no freshness keyword). Options: tiny intent classifier, or declare search as a function the model can *request* (server executes → keeps the gate server-owned).
4. **503 resilience** — retry-on-503 via `gemini-2.5-flash` as a same-provider fallback (separate capacity pool); OpenAI/Anthropic slots exist behind the provider interface when keys arrive.

### M1 (private beta, spec §9)

- **Voice in + spoken caption** — Sarvam Saarika ASR (₹0.05/query) + Bulbul TTS for the caption line (already streams first). Sarvam signup is self-serve (user).
- **Real intent router** — replace the keyword stub (language-ID → normalize → intent; the seam is `router.py`, one function).
- **Trains via deep-links** (DeepLinkCard is spec'd; no API needed pre-TIES), movies/OTT + recipes categories.
- **Basic analytics** — the typed event stream (follow_up_selected, source_opened, …) is designed for this; wire to a sink.
- **100-user beta** — needs: hosted server (currently laptop), crash reporting, grounded-query UX (show grounded text as Markdown immediately, upgrade to composed surface — hides the 15s two-phase latency).

### M2 (monetization + launch prep)

- Action components (UpiPayButton, AffiliateCta, ConsultReferralCard, DeepLinkCard, AdSlot) — contracts frozen in COMPONENT_CATALOG.md §7.4; validator rules R5/R6 already enforce disclosure/placement.
- **The design pass** — layer 3 of the original plan: one polished implementation per catalog component; every answer inherits it.
- Paper track (start now, they're slow): DPIIT recognition → TIES filing; TMDB commercial agreement; cricket legal opinion.

## Milestone tracker (spec §9)

- **M0 (weeks 1–3)**: app + renderer + 8 components ✅ · hi/en/te input ✅ · te output ✅ · <4s answers ✅ hero + ✅ generic ungrounded (p50 5s) / ⚠ grounded (~15s) · "real APIs" ⚠ 1 of 3 (AQI live; cricket+panchang+weather fixtures) · **beyond-M0 extras shipped**: search grounding + sources, multi-turn context, live surfaces, provider abstraction, conversation persistence
- **M1 (weeks 4–8)**: not started — voice, 6 hero categories, 100-user beta
- **M2 (weeks 9–14)**: not started — monetization components, TIES filing, legal opinions
