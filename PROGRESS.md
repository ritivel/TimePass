# TimePass — Progress

**Updated:** 2026-07-09 · living document, newest state first.
Companion docs: `PRODUCT_SPEC.md` (what & why) · `COMPONENT_CATALOG.md` (UI contract) · `README.md` (how to run).

## Where we are, in one paragraph

The M0 vertical slice is **built, tested, and running on a real phone**, and the app now has **voice in + voice out** (Sarvam Saaras ASR with automatic language detection, Bulbul TTS speaking the caption) and a **Monogram-style progressive grounded UX**: time-sensitive queries stream the search-grounded answer into a live Markdown preview from **~2.7s** (caption ~3s, sources ~5.5s), then the composed visual surface replaces it — the old 15–18s blank wait is gone, and if the compose pass fails the user keeps the grounded answer instead of an apology. Gemini 503s now fail over to `gemini-2.5-flash` (separate capacity pool). Freshness-gate misses are covered twice: new commercial-offer keywords (recharge/tariff/offers, hi/te too) and a `needsSearch` escape hatch the model can invoke (server still owns the gate). Connectors (cricket/panchang/weather) are **deliberately deprioritized** — fixtures until later. And the hero/generic split is now **unified**: adapters are model-requestable data sources (`{"needsData": {"source": "aqi"}}` → server fetches → model composes with `/aqi` bindings), so paraphrased queries the keyword router misses ("is the air very polluted in delhi") still reach real CPCB data (~5s, verified live). The keyword router remains as a pure latency cache for exact matches (<0.5s).

## Scoreboard (measured, not vibes)

| Metric | Value | How measured |
|---|---|---|
| Generic-tier validity | **29/30 (97%)**, 0 hard errors | `server/evals/run_evals.py`, 30 diverse queries en/hi/te |
| First visual response | **~0.4s** (placeholder skeleton) | streamed message timestamps |
| Caption (TTS line) | **p50 1.25s** / p90 4.2s | eval harness |
| Full validated surface | **p50 5.0s** / p90 8.5s | eval harness |
| Grounded (search) queries | **first content ~2.7s** (streamed preview; caption ~3s, sources ~5.5s); composed surface ~15–18s replaces it in place | live tests 2026-07-09 |
| Voice round-trip | TTS + ASR verified live (te-IN round-trip exact, language_probability 1.0); caption TTS server-cached | curl + /v1/asr /v1/tts smoke |
| Hero answers (cached path) | instant (<0.5s); cricket refreshes every 8s while live | template + adapter, no LLM |
| Tests | 55 server + 5 Flutter renderer, all green | `uv run pytest` / `flutter test` |
| Unified data path (router-miss hero query) | caption 3.5s, composed hero surface 4.9s, real CPCB data, 0 search spend | live smoke 2026-07-09 |

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
| Sarvam (ASR/TTS) | ✅ live | `saaras:v3` ASR (auto language detect; **Saarika is deprecated**, docs 2026-07) + `bulbul:v3` TTS via server `/v1/asr` `/v1/tts`; key stays server-side (SSM `/shared/sarvam-api-key`, **rotate at some point** — passed through chat). TTS responses LRU-cached. |
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
- **Prompt-only search discipline fails even for punting**: told to reply `{"needsSearch": true}` for current-data questions, Flash-Lite still confidently answered stale telecom prices. Deterministic gate keywords are the primary defense; `needsSearch` only catches the long tail.
- **But topic-scoped punting works**: the same model reliably emits `{"needsData": {"source": "aqi"}}` for paraphrased AQI queries. Enumerated concrete topics ("questions about air quality") discipline the model where open-ended judgments ("questions needing current data") don't.
- **A Markdown component bound to a data-model path is a free streaming text surface** — push `updateDataModel` as chunks arrive, and the client re-renders with zero component regeneration (same trick as live cricket).
- **Sarvam: Saarika is deprecated** — use `saaras:v3` with `mode=transcribe`; it auto-detects language (returns `language_code` + probability), so voice queries need no language picker. TTS `bulbul:v3` wants commas in numbers >4 digits ("10,000") for correct pronunciation; ≤2500 chars; returns base64 WAV. Auth header is `api-subscription-key`; failures are 403 not 401.
- FastAPI `UploadFile` silently requires the `python-multipart` package.
- `dart:io` in any imported file breaks `flutter build web` — use `cross_file`'s `XFile`, which reads both file paths and web blob URLs (record's `stop()` returns the latter on web).

## Roadmap

### Near term

1. ~~Rebuild the phone app~~ — done 2026-07-08 (standalone APK over Wi-Fi). Rebuilt 2026-07-09 with voice.
2. ~~Freshness-gate refinement~~ — done 2026-07-09: commercial-offer keywords + `needsSearch` model escape hatch (server-owned gate preserved).
3. ~~503 resilience~~ — done 2026-07-09: MODEL → retry → `gemini-2.5-flash` ladder on both stream and repair paths.
4. ~~Grounded-latency UX~~ — done 2026-07-09: streaming Markdown preview (data-model bound) from ~2.7s; compose upgrades in place; compose failure keeps the grounded text.
5. ~~Voice~~ — done 2026-07-09: server `/v1/asr` + `/v1/tts` (Sarvam), app mic button (tap-record-tap-stop → transcribe → query in detected language), spoken captions for voice queries, tap any caption's 🔊 to replay. **Untested on the physical device** — needs a mic-permission + round-trip check on the S23 FE.
6. ~~Tool-calling unification~~ — done 2026-07-09: `needsData` requests on the fast path (whitelisted adapter names; unknown source escalates to grounded search); adapter JSON goes to the model in the compose prompt AND into the surface dataModel, so hero components bind `/{source}/...` exactly like server templates. Keyword router kept as latency cache. Known limitations: needsData is fast-path only (freshness-keyword queries go to search even for hero topics, e.g. "delhi aqi **today**" — acceptable, still correct); unified cricket surfaces don't register for live refresh (exact-keyword path does). Rationale for the design: catalog-based declarative gen-UI (A2UI) is the industry-consensus pattern (validated 2026-07-09 against A2UI v0.9 release, AG-UI/Open-JSON-UI/json-render landscape); the brittle part was intent, not rendering.
7. **Connectors** (deprioritized by decision 2026-07-08): weather blocked on IMD approval; panchang needs Prokerala signup (user); cricket is a commercial call (EntitySport ~$150/mo).

### M1 (private beta, spec §9)

- ~~Voice in + spoken caption~~ — shipped early (see near-term #5).
- ~~Real intent router~~ — superseded by tool-calling unification (near-term #6).
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
