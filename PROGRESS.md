# Nakul — Progress

**Updated:** 2026-07-12 · living document, newest state first.
Companion docs: `PRODUCT_SPEC.md` (what & why) · `COMPONENT_CATALOG.md` (UI contract) · `DESIGN.md` (style bible) · `DESIGN_RESEARCH.md` (design evidence) · `README.md` (how to run).

## Round 8 — public-launch abuse and retention hardening

The no-login guest entry is now protected by Cloudflare Turnstile on Android
and web whenever the production site key is present. The resulting token is
passed to Supabase for anonymous signup, email signup, password login, and
password recovery; auth fails closed after a 20-second challenge timeout. The
mobile challenge uses a one-pixel headless WebView so it does not allocate a
full-screen off-screen render target. Production web deployment requires the
Turnstile site key and registered HTTPS origin, while unconfigured local builds
retain the previous developer path.

Supabase Cron now removes unconverted anonymous accounts (and cascading chat /
quota rows) after 30 days, product events after 90 days, and old Cron run logs
after 30 days. The account menu also exposes a JSON data export, and the in-app
privacy policy states the executable retention periods.

The server-owned guest counter now runs as `SECURITY INVOKER` with execution
granted only to the service role; it no longer uses a public
`SECURITY DEFINER` routine. Cloudflare Pages uses the current JSONC Wrangler
configuration and pins direct uploads to the production `main` branch.

Verification on 2026-07-12: all three Cron jobs active after a clean migration
reset; clean Supabase DB lint and Flutter analyzer; 16 Flutter tests; web release
build; 61.3 MB Android App Bundle; and Pixel API 35 cold-launch with the
Cloudflare test widget, direct guest Home (no login), 0-of-5 account status, and
working JSON export. Evidence is under `output/android-qa/turnstile/`.

## Round 7 — account-backed product foundation

Nakul now opens directly into a Supabase anonymous session instead of a login
wall. Five real questions are available as a guest; the fifth answer opens a
"Keep your chats" sheet, the sixth is blocked both in Flutter and by an atomic
server-owned Supabase quota, and email/Google identity linking upgrades the same
user so chat rows remain in place. Existing-account sign-in carries a local
handoff copy into the signed-in account. The app adds cloud-synced conversation
documents, distinct chat history, rename/delete, bookmarks, password recovery,
account deletion, account/legal screens, and write-only product events.

The FastAPI API now validates every paid-route bearer token with Supabase,
scopes live surfaces to their owner, limits audio uploads, avoids logging query
content, emits correlation IDs and security headers, fails startup when
production auth configuration is incomplete, and keeps the privileged secret
on the server. RLS and explicit Data
API grants were exercised with two real local Auth users: cross-user reads and
updates were invisible, ownership spoofing returned 403, and analytics remained
write-only. Render Docker, Cloudflare Pages, production Android, legal, and
deployment artifacts live in `render.yaml`, `server/Dockerfile`, `app/wrangler.toml`,
and `DEPLOYMENT.md`.

Verification on 2026-07-12: 68 server tests, 16 Flutter tests, clean analyzer,
clean Supabase DB lint, web release build, 60 MB Android App Bundle, catalog-aware
Docker health smoke, and Pixel API 35 emulator flows for guest Home → five
answers → upgrade gate → email identity → retained five chats → sixth answer.
Evidence is under `output/android-qa/`.

## Round 6 — dynamic visual answers + release hardening

The app now composes answers by intent instead of relying on a fixed screen template. The live
catalog has **24 components (15 custom)** and adds `GeneratedVisual`, `ChartCard`,
`TimelineCard`, and the interactive `RecipeCard`. The model chooses a compact answer structure;
the server validates it, guarantees contextual follow-ups, and injects at most one generated
visual where imagery materially helps. Visual prompts only describe subject/composition: the
server owns a fixed Nakul soft-3D art direction, forbids text/maps/logos/URLs, calls
`gemini-3.1-flash-image`, deduplicates concurrent requests, and caches results in memory and on
disk. A restart-cache smoke reduced the same 137 KB image from **7.27s to 1.6ms**.

The Flutter release now has a dedicated answer header, bookmarks and persisted history that
restore to Home, contextual continuation cards, system light/dark mode, a fully blocked and
accessible voice-focus overlay, tappable recipe steps, native bar/line/donut charts, itineraries,
generated-image loading/retry states, and a real Nakul launcher/PWA icon. Android package id is
`app.nakul.mobile`. The exact release APK was exercised on a Pixel 7 API 35 emulator: English
recipe → generated hero image → step 2 → bookmark → back → force-stop/relaunch → saved answer
reopen, plus silent-voice recovery and accessibility-tree checks. Live generic smokes also chose
`ChartCard`, `TimelineCard`, and recipe + generated visual in English, Hindi, and Telugu.

Final automated evidence: **63 server tests**, **16 Flutter tests**, clean `flutter analyze`, and a
58 MB release APK. Monogram/reference side-by-side evidence and critique history live in
`design-qa.md` and `output/design-qa/answer-recipe-comparison.png`.

Phone handoff artifact: `output/android/Nakul-phone-192.168.1.6.apk`, SHA-256
`7b5642f986590470676a6e8987fdd0ee05f3a0bb772e05875474becda22b11bb`. It was installed with
`adb reverse` removed and fetched a generated recipe visual over the LAN successfully.

## Round 5 — the design pass ("Quiet Interface")

Deep research first (110-agent verified run → `DESIGN_RESEARCH.md`): Monogram's own careers page frames motion craft on a small set of polished primitives as the product (2 of 7 openings are design roles) — which is exactly our catalog architecture; plus verified evidence on citation-trust (1–2 real sources beat many), latency psychology (>4s degrades; subtle/conversational waiting states beat spinners), and Indic type rules (fixed line-heights, no heavy bolds).

First attempt was **"Station Board"** (Indian Railways signage: yellow query strips, enamel blue, bundled Anek fonts) — user rejected it (too loud, wanted the Monogram feel), and a live teardown of monogram.ai confirmed their language is the opposite: **quiet chrome, colorful content**. Final system (`DESIGN.md`, `app/lib/theme/`): white surfaces; near-black as the only chrome accent (big round mic, buttons); soft gray tiles, radius 20, no borders; white cards floating on soft shadows; semibold sentence-case section headers; gray query bubbles; `ThinkingDots` instead of spinners; semantic color only inside content (CPCB AQI bands, W/4/6 balls, IMD alerts, LIVE lamp); system fonts (Anek dropped, −4.4 MB). Empty state = 2×2 grid of **generated soft-3D objects** (`gpt-image-1.5`, transparent, de-glowed, 16–28 KB WebP each: cricket ball, sun-cloud, diya, leaf) firing trilingual sample queries — the Monogram ingredient-tile pattern. All 11 components re-skinned, shell rebuilt, 5/5 contract tests green, analyzer clean, verified in-browser light+dark (`design-*.png`).

Learned this round: gpt-image-2 has no transparent-background param (use 1.5 for isolated objects) and models bake ambient glow even when told not to — de-glow programmatically (alpha threshold) before shipping; never case-transform server content (uppercase broke text-fidelity tests and is meaningless for Indic); `Future.delayed` in entrance animations leaves pending timers in widget tests (use cancelable `Timer`); a `TpCard` built from a plain decorated `Container` breaks `CheckboxListTile` ink (needs a `Material` surface); theme extensions need brightness fallbacks so catalog components render under any host theme. Remaining design work in `DESIGN.md` §open (more category objects, Rive mic moment, stagger, streaming shimmer, low-end QA).

## Where we are, in one paragraph

Everything below is now **verified on the physical S23 FE** (2026-07-09, APK installed over wireless adb, server on the laptop's LAN IP): the app has **voice in + voice out** (Sarvam Saaras ASR with automatic language detection, Bulbul TTS speaking the caption — mic → `/v1/asr` → transcript and caption-🔊 → `/v1/tts` → audio both round-tripped on device; real speech still untested, only ambient silence), a **Monogram-style progressive grounded UX** (time-sensitive queries stream the search-grounded answer into a live Markdown preview from **~2.7s**, caption ~3s, sources ~5.5s; the composed surface replaces it in place; compose failure keeps the grounded text), and a **unified data path**: the hero/generic split is gone — adapters are model-requestable data sources (`{"needsData": {"source": "aqi"}}` → server fetches → model composes with `/aqi` bindings), so paraphrased queries the keyword router misses ("is the air very polluted in delhi") render a real CPCB AqiMeter on the phone in ~5s. The keyword router remains as a pure latency cache (<0.5s exact matches). Gemini 503s fail over to `gemini-2.5-flash`; freshness-gate misses are covered by commercial-offer keywords plus the `needsSearch` escape hatch. Connectors (cricket/panchang/weather) stay **deliberately deprioritized** — fixtures until later.

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
| Tests | 63 server + 16 Flutter, all green; analyzer clean | `uv run python -m pytest -q` / `flutter test` / `flutter analyze` |
| Dynamic answer E2E | recipe image + interactive steps + bookmark + restart restore; chart/timeline + hi/te generation smokes | Pixel 7 API 35 release APK + live API, 2026-07-10 |
| Unified data path (router-miss hero query) | caption 3.5s, composed hero surface 4.9s, real CPCB data, 0 search spend | live smoke + on-device 2026-07-09 |
| On-device E2E (S23 FE, Wi-Fi, no adb bridge) | unified AQI surface, chips round-trip, TTS playback, ASR upload — all working | adb-driven session 2026-07-09 |

Grounding-gate history (same 30-query set): always-ground → 26/30 valid, caption p50 **14.4s**, 70–77% of queries searched; prompt-only discipline → no improvement; **server-side freshness gate → 29/30, caption p50 1.25s, 1/30 searched**. The model will not self-limit search; the server must decide.

## What's built (by layer)

**Catalog (`catalog/`)** — single source of truth `catalog.yaml` → generator emits `catalog.json` (validation schema), `system_prompt.md` (LLM prompt fragment), `schemas.g.dart` (Flutter). **24 components are live**: 10 adopted primitives + 15 custom renderer items, including structured comparison/checklist/source components and the new `GeneratedVisual`, `ChartCard`, `TimelineCard`, and `RecipeCard`. Reserved monetization and future-data components remain frozen in `COMPONENT_CATALOG.md`.

**Server (`server/`)** — FastAPI orchestrator: keyword intent router (M0 stub) → hero templates with data-model bindings OR streaming generic tier → **fail-closed catalog validator** (nothing off-catalog ever ships) → A2UI v0.9-wire NDJSON. The generic tier lives behind a **provider interface** (`llm/base.py`; Gemini in `llm/gemini.py`, selected by `LLM_PROVIDER`): freshness-gated search grounding (grounded plain-text answer → strict-JSON compose pass; sources → server-built SourceChips), client-supplied conversation history (stateless server), shape normalizer + validation-feedback retry + 503 backoff. `/v1/visual` applies the server-owned art direction and persistent cache. **Live surfaces**: `GET /v1/live/{surface_id}` pushes `updateDataModel` refreshes until TTL (cricket: every 8s). Eval harness in `server/evals/`.

**App (`app/`)** — Flutter + genui 0.9.2. Every live catalog item has one polished Quiet Interface renderer; `{path}` bindings resolve reactively, follow-up chips / checklist toggles / source taps / recipe steps round-trip as typed events. Conversations and bookmarks persist across restarts (raw NDJSON replay via shared_preferences), generated visuals load asynchronously with recovery, live surfaces show a LIVE badge and auto-update, and errors get a friendly retry card. Renderer contract tests replay recorded server streams, including a visual-rich composite surface.

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
- **Captions leak meta-language**: seen on device — a recipe answer's caption was "Here is the JSON requested:" (spoken aloud by TTS!). The contract now says captions are read aloud and must never mention JSON/components/the interface. Watch for regressions in evals.
- **A stale server is invisible until an endpoint 404s**: the phone hit the laptop's long-running uvicorn from a previous day — old code, no `/v1/asr`. After server-side changes, restart the process (check `lsof -iTCP:8000`); the APK doesn't need rebuilding unless the client changed.
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
5. ~~Voice~~ — done 2026-07-09: server `/v1/asr` + `/v1/tts` (Sarvam), app mic button (tap-record-tap-stop → transcribe → query in detected language), spoken captions for voice queries, tap any caption's 🔊 to replay. Device-verified same day: mic permission, record/stop toggle, ASR upload (empty ambient transcript safely no-ops), TTS playback. **Remaining: a real spoken query in hi/te** (only ambient silence was tested — nobody spoke to the phone).
6. ~~Tool-calling unification~~ — done 2026-07-09: `needsData` requests on the fast path (whitelisted adapter names; unknown source escalates to grounded search); adapter JSON goes to the model in the compose prompt AND into the surface dataModel, so hero components bind `/{source}/...` exactly like server templates. Keyword router kept as latency cache. Known limitations: needsData is fast-path only (freshness-keyword queries go to search even for hero topics, e.g. "delhi aqi **today**" — acceptable, still correct); unified cricket surfaces don't register for live refresh (exact-keyword path does). Rationale for the design: catalog-based declarative gen-UI (A2UI) is the industry-consensus pattern (validated 2026-07-09 against A2UI v0.9 release, AG-UI/Open-JSON-UI/json-render landscape); the brittle part was intent, not rendering.
7. **Connectors** (deprioritized by decision 2026-07-08): weather blocked on IMD approval; panchang needs Prokerala signup (user); cricket is a commercial call (EntitySport ~$150/mo).

### M1 (private beta, spec §9)

- ~~Voice in + spoken caption~~ — shipped early (see near-term #5).
- ~~Real intent router~~ — superseded by tool-calling unification (near-term #6).
- **Trains via deep-links** (DeepLinkCard is spec'd; no API needed pre-TIES) and movies/OTT. Recipe composition is shipped.
- **Basic analytics** — the typed event stream (follow_up_selected, source_opened, …) is designed for this; wire to a sink.
- **100-user beta** — needs: hosted HTTPS server (currently laptop), owner release signing, crash reporting, and analytics. Progressive grounded-query UX is already shipped.

### M2 (monetization + launch prep)

- Action components (UpiPayButton, AffiliateCta, ConsultReferralCard, DeepLinkCard, AdSlot) — contracts frozen in COMPONENT_CATALOG.md §7.4; validator rules R5/R6 already enforce disclosure/placement.
- ~~**The core design pass**~~ — shipped for all 24 live catalog components; future reserved components are polished as they enter the live catalog.
- Paper track (start now, they're slow): DPIIT recognition → TIES filing; TMDB commercial agreement; cricket legal opinion.

## Milestone tracker (spec §9)

- **M0 (weeks 1–3)**: app + renderer + 8 components ✅ · hi/en/te input ✅ · te output ✅ · <4s answers ✅ hero + ✅ generic ungrounded (p50 5s) / ⚠ grounded (~15s) · "real APIs" ⚠ 1 of 3 (AQI live; cricket+panchang+weather fixtures) · **beyond-M0 extras shipped**: search grounding + sources, multi-turn context, live surfaces, provider abstraction, conversation persistence
- **M1 (weeks 4–8)**: in progress — voice ✅ · dynamic recipe/chart/timeline/visual answers ✅ · hosted 100-user beta pending
- **M2 (weeks 9–14)**: not started — monetization components, TIES filing, legal opinions
