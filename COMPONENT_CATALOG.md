# Component Catalog Contract — v1

**Version:** 1.0-draft · 2026-07-08
**Status:** Contract for M0 build. Freezes names, props, events, and composition rules. Visual design is deliberately deferred to the post-M0 design pass — nothing in this document constrains aesthetics except structure.
**Protocol target:** A2UI **v0.9.1** (current production release; v1.0 is a release candidate — see §12).
**Renderer target:** Flutter via `package:genui` + `genui_a2a` (the official A2UI Flutter path).

---

## 1. How this contract is used

One catalog, consumed in three places. This document is the single source of truth for all three:

1. **Server (agent):** the catalog JSON Schema + its `instructions` field are compiled into the Gemini Flash-Lite system prompt (mirroring what `PromptBuilder` does client-side). The model may only emit components defined here.
2. **Flutter app:** each component maps to one `CatalogItem` (`name` + `dataSchema` + `widgetBuilder`) registered on the `SurfaceController`. The renderer rejects anything not in the catalog — this is the security boundary.
3. **Design pass (post-M0):** each component below gets exactly one polished implementation; every answer in the app inherits it.

**Authoring rule:** the catalog is *authored* in a source file (Dart or YAML) and *generated* to `catalog.json`. A2UI v1.0 prohibits custom `$defs` inside a catalog (only `surfaceProperties` / `anyComponent` / `anyFunction` are allowed), so the shared shapes in §8 are inlined into each component's schema by the generator, not `$ref`'d.

## 2. Protocol ground rules (verified against spec)

- **Naming:** all component, prop, and event names MUST follow UAX #31 identifier rules — letters/underscore start, no hyphens, no spaces. The spec's working names (`scorecard-live` etc.) are therefore renamed here: `CricketLiveScore`, not `scorecard-live`. Components are `PascalCase`, props `camelCase`, events `snake_case`.
- **Wire format (v0.9.1):** flat adjacency list, not nested trees. Every component instance is `{"id": "...", "component": "<Name>", ...props}`; containers reference children by id arrays.
- **Data binding:** any leaf prop may be a literal (`"text": "40 min late"`) or a binding (`"text": {"path": "/train/12301/delayText"}`). Server-side data adapters write hero payloads into the surface data model (`updateDataModel`); the LLM binds paths instead of inlining data. This is our token-economy lever: the model composes structure, adapters carry data.
- **Actions:** interactive components carry `"action": {"event": {"name": "<event>", "context": {...path bindings...}}}`. Events land back at the orchestrator as typed messages, never free text.
- **v0.9 renames apply everywhere:** `variant` (not `usageHint`), `justify`/`align` (not `distribution`/`alignment`), `action` (not `userAction`), `value` (not `text`) on inputs.

## 3. Design principles

1. **Coarse hero, fine generic.** Hero-category answers are single rich components (`CricketLiveScore`, `PanchangCard`) with fixed internal layout — deterministic, cheap to generate, guaranteed polish. The generic tier composes primitives (`Card`, `Column`, `ComparisonTable`, `Markdown`). The model never rebuilds a scorecard out of Rows.
2. **Prose is a first-class answer.** `Markdown` exists so "write a leave letter" is *not* forced into cards.
3. **Data flows through the data model, structure through components.** Anything that updates (live scores, train position) is a binding; the server refreshes the data model and the UI updates without re-generation.
4. **Compliance is structural, not behavioral.** Legal/disclosure requirements (cricket lag, astrology disclaimer, ad labeling, JustWatch attribution) are *props and composition rules*, enforced by a server-side validator — not prompt suggestions.
5. **Monetization is a component type.** Action components (§7.4) are ordinary catalog entries the model composes into answers. Design metric from the product spec: ≥1 action surface per session.
6. **Every string the user sees arrives in the output language** (hi/en/te), produced by the model or by localized adapter templates. Components never hardcode display text; the renderer never translates.

## 4. Component inventory

**35 total = 10 adopted primitives (free with the Basic Catalog renderer) + 25 custom (our design-pass scope — matches the spec's "~25").**

| # | Component | Layer | M0 | Container? | Purpose |
|---|-----------|-------|----|-----------|---------|
| 1 | `Text` | primitive | ✅ | – | Single-style text run (variants h1–label) |
| 2 | `Markdown` | primitive | ✅ | – | Prose answers, GFM subset |
| 3 | `Image` | primitive | ✅ | – | Remote image w/ variant sizing |
| 4 | `Icon` | primitive | ✅ | – | Named icon from app icon set |
| 5 | `Row` | primitive | ✅ | ✅ | Horizontal layout |
| 6 | `Column` | primitive | ✅ | ✅ | Vertical layout (surface root) |
| 7 | `Card` | primitive | ✅ | ✅(1) | Grouping container, tappable |
| 8 | `List` | primitive | ✅ | ✅ | Scrollable list, vertical/horizontal |
| 9 | `Button` | primitive | ✅ | ✅(1) | Generic action trigger |
| 10 | `Divider` | primitive | ✅ | – | Visual separator |
| 11 | `KeyValueGrid` | generic | ✅ | – | Labeled facts (1–2 columns) |
| 12 | `ComparisonTable` | generic | – | – | N-way comparisons (MF vs FD…) |
| 13 | `Checklist` | generic | – | – | Check-off / diagnostic lists |
| 14 | `MediaCarousel` | generic | – | – | Horizontal poster/card rail (OTT, places) |
| 15 | `MapCard` | generic | – | – | Static map + markers + open-in-maps |
| 16 | `ChartCard` | generic P1 | – | – | Simple bar/line/donut |
| 17 | `Notice` | generic | ✅ | – | Info/warning/legal callout |
| 18 | `SourceChips` | generic | – | – | Web-source attribution chips |
| 19 | `FollowUpChips` | generic | ✅ | – | Suggested next queries |
| 20 | `CricketLiveScore` | hero | ✅ | – | Live match card (lagged) |
| 21 | `CricketMatchSummary` | hero | – | – | Finished/upcoming match card |
| 22 | `TrainStatusTimeline` | hero | – | – | Live running status, station list |
| 23 | `PnrStatusCard` | hero | – | – | PNR + passenger statuses |
| 24 | `PanchangCard` | hero | ✅ | – | Daily panchang for a location |
| 25 | `MuhuratList` | hero | – | – | Auspicious time windows |
| 26 | `HoroscopeCard` | hero | – | – | Daily horoscope by sign |
| 27 | `WeatherStrip` | hero | ✅ | – | Current + N-day forecast |
| 28 | `AqiMeter` | hero | ✅ | – | AQI gauge + health advice |
| 29 | `PriceTicker` | hero | – | – | Gold/fuel/commodity prices |
| 30 | `RecipeCard` | hero | – | – | Ingredients + steps + timers |
| 31 | `UpiPayButton` | action | – | – | UPI intent deep-link |
| 32 | `AffiliateCta` | action | – | – | Disclosed partner CTA |
| 33 | `ConsultReferralCard` | action | – | – | Astro-consult referral |
| 34 | `DeepLinkCard` | action | – | – | Open external app w/ fallback |
| 35 | `AdSlot` | action | – | – | Native ad placeholder |

M0 custom set is exactly 8 (`KeyValueGrid`, `Notice`, `FollowUpChips`, `CricketLiveScore`, `PanchangCard`, `WeatherStrip`, `AqiMeter`) + `Markdown`, satisfying the M0 milestone ("8 components, cricket + panchang + weather"). Primitives ship with the renderer.

## 5. Composition rules

**R1 — Surface root.** Every answer surface is one `Column` whose children follow this template:

```
Column (root)
 ├─ [0..1] Notice            (compliance, if category requires — see R6)
 ├─ [1..8] answer blocks      (hero components, Card/Markdown/generic components)
 ├─ [0..1] action block       (UpiPayButton | AffiliateCta | ConsultReferralCard | DeepLinkCard)
 ├─ [0..1] SourceChips        (required when web search was used)
 ├─ [0..1] AdSlot             (never the first child; ≤1 per surface)
 └─ [0..1] FollowUpChips      (always last; default: present)
```

**R2 — Containers.** Only `Row`, `Column`, `Card`, `List` accept `children` (Card and Button take a single `child`). All generic/hero/action components are leaves — the model cannot inject arbitrary content inside them.

**R3 — Depth & size.** Max nesting depth 4 from root; ≤ 40 component instances per surface; `Row` ≤ 4 children. Enforced by the server-side validator before the payload ships.

**R4 — Hero exclusivity.** ≤ 2 hero components per surface (e.g. `WeatherStrip` + `AqiMeter` is the canonical pair). Hero components are never wrapped in `Card` (they are already cards).

**R5 — One action rule.** ≤ 1 monetization/action component per surface. Which one is category-driven: astrology → `ConsultReferralCard`; trains → `DeepLinkCard`/`AffiliateCta` (cross-sell); recipes → `AffiliateCta` (grocery); cricket → `AdSlot` only.

**R6 — Mandatory compliance composition** (validator-enforced, not model-trusted):
- `CricketLiveScore` present → root must contain `Notice(variant: legal)` with the lag disclosure, and `lagSeconds` must be ≥ the configured buffer.
- `HoroscopeCard` / `MuhuratList` present → `Notice(variant: info)` with the "for guidance only" disclaimer.
- `AffiliateCta` / `ConsultReferralCard` / `AdSlot` render their own disclosure label (prop, non-optional).
- `MediaCarousel` with `attribution: "justwatch"` renders the JustWatch credit (TMDB terms).

**R7 — Language.** The orchestrator injects `outputLanguage` (hi/en/te) into the generation context; every generated string prop must be in that language. Numbers use Latin digits in all three languages (v1 decision — revisit with user research). Dates/times arrive pre-formatted from adapters (`"6:47 AM"`, `"रात 9:32 बजे तक"`), never computed by the model.

## 6. Shared value shapes

Inlined by the catalog generator wherever referenced (see §1 authoring rule):

```jsonc
ActionSpec   = { "event": { "name": string, "context": object } }   // A2UI standard
Trend        = { "direction": "up"|"down"|"flat", "amountText": string, "pctText"?: string }
TimeWindow   = { "startText": string, "endText": string }           // pre-formatted, localized
LinkTarget   = { "url": string, "fallbackUrl"?: string }            // deep link + web/store fallback
Badge        = { "text": string, "tone": "neutral"|"positive"|"warning"|"live" }
```

All string props are `DynamicString` on the wire (literal or `{path}` binding); array/object props are similarly Dynamic. Not repeated per-component below.

## 7. Component contracts

Format per component: purpose → props (required **bold**) → events → wireframe. Wireframes are structural only.

### 7.1 Primitives (adopted from Basic Catalog, constrained)

We adopt the Basic Catalog definitions with narrowed enums; no wireframes (renderer-standard).

| Component | Props (ours) | Notes |
|---|---|---|
| `Text` | **`text`**, `variant: h1\|h2\|h3\|body\|caption\|label` | h1 reserved for surface title |
| `Markdown` | **`text`** | GFM subset: bold/italic/lists/tables/links; no raw HTML, no images |
| `Image` | **`url`**, `alt`, `variant: avatar\|thumbnail\|feature\|hero`, `fit: cover\|contain` | https only; adapter-proxied domains allowlist |
| `Icon` | **`name`** (enum, app icon set ~60 names), `size: sm\|md\|lg` | Icon set frozen at design pass |
| `Row` | **`children`**, `justify`, `align`, `gap: none\|sm\|md\|lg`, `wrap` | ≤4 children (R3) |
| `Column` | **`children`**, `justify`, `align`, `gap` | Surface root |
| `Card` | **`child`**, `variant: elevated\|outlined\|filled`, `action?` | Tappable when `action` set |
| `List` | **`children`**, `direction: vertical\|horizontal` | Horizontal = generic rail |
| `Button` | **`child`**, **`action`**, `variant: primary\|secondary\|text\|destructive`, `enabled` | |
| `Divider` | – | |

### 7.2 Generic answer components

#### 11. `KeyValueGrid`
Labeled facts: specs, statuses, summaries. The workhorse of the generic tier.
- **`items`**: `[{ label, value, icon?, emphasis?: bool }]` (1–12)
- `columns: 1|2` (default 2), `title?`

```
┌────────────────────────────────┐
│ Title?                         │
│ ⛅ Label      🌡 Label          │
│    Value        Value          │
│ 💧 Label      🌬 Label          │
│    Value        Value          │
└────────────────────────────────┘
```

#### 12. `ComparisonTable`
N-way comparison ("mutual funds vs FD vs gold").
- **`columns`**: `[{ key, label }]` (2–4) · **`rows`**: `[{ label, cells: [string] }]` (≤10)
- `title?`, `highlightColumnKey?` (the recommendation), `footnote?`

```
┌────────────────────────────────┐
│ Title                          │
│          │ MF      │▐ FD ▌     │
│ Returns  │ 12–15%  │▐ 7% ▌     │
│ Risk     │ Market  │▐ Low ▌    │
│ Lock-in  │ None    │▐ 5yr ▌    │
│ footnote                       │
└────────────────────────────────┘
```

#### 13. `Checklist`
Diagnostic / to-do / packing lists ("why is my tulsi dying").
- **`items`**: `[{ id, text, detail?, checked?: bool }]` (≤24 — weekly plans and packing lists run long)
- `title?`, `interactive: bool` (default false)
- Events: `checklist_toggled { itemId, checked }` (only when interactive)

```
┌────────────────────────────────┐
│ Title                          │
│ ☑ Item text                    │
│ ☐ Item text                    │
│    └ detail line               │
│ ☐ Item text                    │
└────────────────────────────────┘
```

#### 14. `MediaCarousel`
Horizontal rail of visual items: OTT picks, weekend places, products.
- **`items`**: `[{ id, imageUrl, title, subtitle?, badge?: Badge, rating?, meta? }]` (2–10)
- `title?`, `itemAspect: poster|landscape|square`, `attribution?: justwatch|tmdb|none`
- Events: `carousel_item_selected { itemId }`

```
 Title
 ┌────┐ ┌────┐ ┌────┐
 │img │ │img │ │img │ →
 │    │ │    │ │    │
 └────┘ └────┘ └────┘
 Title   Title  Title
 sub     sub    sub
 ⓘ attribution
```

#### 15. `MapCard`
Static map snapshot + markers; tap opens maps app.
- **`center`**: `{ lat, lng }` · `zoom`, **`markers`**: `[{ id, lat, lng, label }]` (≤8), `height: sm|md`
- Events: `map_opened { markerId? }` (also fires `openUrl` client function → geo/maps deep link)

```
┌────────────────────────────────┐
│        ▲2                      │
│   ▲1        [map area]         │
│              ▲3                │
│ ①Label ②Label ③Label  [Open ↗]│
└────────────────────────────────┘
```

#### 16. `ChartCard` *(P1 — not in v1 build; contract reserved)*
- **`type`**: `bar|line|donut` · **`series`**, `title?`, `xLabels?`, `unit?`

#### 17. `Notice`
Callouts and compliance surface (R6).
- **`text`** · `variant: info|warning|legal|success` · `icon?`, `dense?: bool`

```
┌────────────────────────────────┐
│ ⚠ Notice text runs here,       │
│   wrapping as needed.          │
└────────────────────────────────┘
```

#### 18. `SourceChips`
Attribution when web search fed the answer.
- **`sources`**: `[{ title, domain, url }]` (1–5)
- Events: `source_opened { url }` (opens in-app browser)

```
 (🌐 ndtv.com) (🌐 cricbuzz…) (+2)
```

#### 19. `FollowUpChips`
Suggested next queries — the retention loop. Always last child (R1).
- **`suggestions`**: `[{ label, query }]` (2–4)
- Events: `follow_up_selected { query }` → orchestrator treats as a new user query

```
 (Kal ka mausam?) (AQI Delhi) (7-day)
```

### 7.3 Hero components

All hero components read their payloads from adapter-populated data-model paths (§2). The prop lists below define both the wire schema and the adapter payload contract.

#### 20. `CricketLiveScore`
- **`matchId`**, **`matchTitle`** ("IND vs AUS · 3rd T20I"), **`statusText`** (localized: "IND need 43 off 30")
- **`teams`**: exactly 2 × `{ name, shortName, logoUrl?, scoreText ("186/4"), oversText ("17.2") }`
- `batters`: `[{ name, runsText ("52*"), ballsText, onStrike: bool }]` (≤2)
- `bowler`: `{ name, figuresText ("2/34"), oversText }`
- `recentBalls`: `[string]` (≤6: "1", "W", "4"…)
- **`lagSeconds`** (drives R6 legal notice), **`updatedAtText`**
- Events: none (auto-refresh via data model; server re-pushes every N sec per match, shared across users)

```
┌────────────────────────────────┐
│ IND vs AUS · 3rd T20I    ●LIVE │
│                                │
│  🇮🇳 IND   186/4   (17.2)      │
│  🇦🇺 AUS   201/7   (20.0)      │
│                                │
│ IND need 43 off 30             │
│ Kohli 52* (31)  •  Rahul 12(8) │
│ Starc 2/34 (3.2)               │
│ ④ ① Ⓦ ⑥ ② •                  │
│ updated 15s ago · 5 min lag ⓘ  │
└────────────────────────────────┘
```

#### 21. `CricketMatchSummary`
Finished or upcoming match.
- **`matchId`**, **`matchTitle`**, **`state`**: `upcoming|finished` · **`resultText`** or **`startTimeText`**
- **`teams`** (as above, scores optional), `playerOfMatch?: { name, statText }`, `venue?`
- Events: `match_details_requested { matchId }` (follow-up generation)

#### 22. `TrainStatusTimeline`
- **`trainNo`**, **`trainName`**, **`statusText`** ("40 min late"), **`delayMinutes`**, `lastLocationText`, **`updatedAtText`**, `dataSourceText` (freshness/source disclosure — pre-TIES this is load-bearing honesty)
- **`stops`**: `[{ code, name, schedText, etaText?, platform?, state: passed|current|upcoming }]` (adapter may truncate to window around current position, ≤12)
- Events: `station_selected { code }`

```
┌────────────────────────────────┐
│ 12301 Rajdhani Exp   ⏱ +40 min │
│ crossed Itarsi · 5 min ago     │
│                                │
│ ● Bhopal      14:35  ✓         │
│ ● Itarsi      16:10  ✓         │
│ ◉ Nagpur      19:55 → 20:35    │
│ ○ Ballarshah  22:04 → 22:44    │
│ ○ Warangal    01:14 → 01:54    │
│ source: NTES via X · 2 min old │
└────────────────────────────────┘
```

#### 23. `PnrStatusCard`
- **`pnrMasked`** ("245-XXXXX78"), **`trainNo`**, **`trainName`**, **`dateText`**, **`fromStation`**, **`toStation`**, `classText` ("3A")
- **`passengers`**: `[{ seq, bookingStatusText ("WL 14"), currentStatusText ("RAC 2"), tone: confirmed|probable|waitlist }]` (≤6)
- `chartStatusText?`
- Events: `pnr_refresh_requested { pnr }` — note: PNR itself lives server-side; wire carries masked form only (DPDP posture)

#### 24. `PanchangCard`
- **`dateText`** (localized, both calendars), **`locationName`**
- **`tithi`**: `{ name, endsAtText }` · **`nakshatra`**: `{ name, endsAtText }` · `yoga?`, `karana?`
- **`sunriseText`**, **`sunsetText`**, **`rahuKalam`**: `TimeWindow`
- `festivals`: `[string]` (today's, ≤3) · `variant: compact|full`
- Cache key: city + date → ~₹0 marginal (spec §6)

```
┌────────────────────────────────┐
│ आज का पंचांग     Hyderabad     │
│ मंगलवार, 8 जुलाई · आषाढ़ शुक्ल   │
│                                │
│ तिथि    चतुर्दशी (रात 9:32 तक)   │
│ नक्षत्र  मूल (शाम 7:14 तक)       │
│ 🌅 5:48   🌇 6:52               │
│ ⚠ राहुकाल  3:30 – 5:00         │
│ 🪔 Festival name               │
└────────────────────────────────┘
```

#### 25. `MuhuratList`
- **`title`**, **`purpose`**: `marriage|grihaPravesh|vehicle|travel|business|generic`
- **`items`**: `[{ dateText, window: TimeWindow, quality: shubh|neutral|avoid, note? }]` (≤8)
- R6: requires info disclaimer notice on surface.

#### 26. `HoroscopeCard`
- **`sign`** (enum 12), **`signLabel`** (localized), **`dateText`**, **`summary`** (2–3 sentences)
- `aspects`: `[{ area: love|career|health|money, rating: 1..5, text }]` (≤4)
- `luckyNumberText?`, `luckyColorText?`
- R6: disclaimer notice required; canonical follow-up composition = `ConsultReferralCard` (R5).

```
┌────────────────────────────────┐
│ ♌ सिंह राशि · 8 जुलाई           │
│ Summary text 2–3 sentences…    │
│ ❤ ★★★☆☆   💼 ★★★★☆            │
│ ➕ ★★★☆☆   ₹ ★★★★★            │
│ Lucky: 9 · हरा                 │
└────────────────────────────────┘
```

#### 27. `WeatherStrip`
- **`locationName`**, **`current`**: `{ tempText, condition (enum→icon), conditionText, feelsLikeText?, humidityText?, windText? }`
- **`days`**: `[{ dayLabel, minText, maxText, condition, rainPctText? }]` (3–7)
- `alerts`: `[{ severity: watch|warning, text }]` (IMD; renders inline warning row)

```
┌────────────────────────────────┐
│ Hyderabad          ⛈ 29°       │
│ Heavy rain · feels 33°         │
│ 💧82%  🌬 14 km/h              │
│ ──────────────────────────────│
│ Wed  Thu  Fri  Sat  Sun        │
│ ⛈    🌧   ⛅   ☀    ☀         │
│ 29°  28°  30°  32°  33°        │
│ 26°  25°  26°  27°  27°        │
└────────────────────────────────┘
```

#### 28. `AqiMeter`
- **`locationName`**, **`aqi`** (number), **`category`**: `good|satisfactory|moderate|poor|veryPoor|severe` (drives color band, CPCB scale), **`categoryText`** (localized)
- `dominantPollutant?`, **`updatedAtText`**, `stationName?`, **`healthAdviceText`**

```
┌────────────────────────────────┐
│ AQI · Anand Vihar, Delhi       │
│      ╭─────────╮               │
│      │   287   │  ▓▓▓▓▓░░     │
│      ╰─────────╯  Poor         │
│ PM2.5 dominant · 20 min ago    │
│ 😷 Advice text line            │
└────────────────────────────────┘
```

#### 29. `PriceTicker`
- **`items`**: `[{ id, label ("Gold 24K · 10g"), priceText ("₹74,250"), trend?: Trend, updatedAtText }]` (1–6)
- `variant: single|strip`

```
┌────────────────────────────────┐
│ Gold 24K · 10g                 │
│ ₹74,250   ▲ +320 (0.4%)        │
│ Petrol Delhi  ₹94.72  ─ 0.0    │
│ updated today 9:00 AM          │
└────────────────────────────────┘
```

#### 30. `RecipeCard`
- **`title`**, `imageUrl?`, **`servesText`**, **`timeText`** ("20 min prep · 30 min cook")
- **`ingredients`**: `[{ name, qtyText, note? }]` (≤20)
- **`steps`**: `[{ text, timerMinutes? }]` (≤12; timer renders a start-timer affordance)
- `tips?: [string]`, `festivalTag?`
- Events: `recipe_timer_started { stepIndex, minutes }`
- Canonical action pairing: `AffiliateCta` (grocery cart) per R5.

```
┌────────────────────────────────┐
│ [image]  Modak                 │
│ 🍽 12 pcs · ⏱ 20+30 min        │
│ ── Ingredients ──              │
│ • चावल का आटा   2 cup           │
│ • गुड़           1 cup           │
│ ── Steps ──                    │
│ ① Step text…                   │
│ ② Step text…       [⏱ 10 min] │
└────────────────────────────────┘
```

### 7.4 Action components (the monetization layer)

All action components: (a) carry a **non-optional disclosure prop** where money is involved, (b) fire an analytics/agent event **and** invoke the `openUrl` client function, (c) are leaves, ≤1 per surface (R5). URLs are always constructed server-side (tracked, signed) — the model never fabricates a payment or affiliate link; the validator rejects literal URLs not issued by the action service.

#### 31. `UpiPayButton`
- **`payeeName`**, **`amountText`** ("₹120") , `noteText?`, **`upiIntentUrl`** (server-issued `upi://pay?...`)
- Events: `upi_pay_initiated { payee, amount }`

```
┌────────────────────────────────┐
│  ⚡ Pay ₹120 · UPI             │
│     to IRCTC eCatering         │
└────────────────────────────────┘
```

#### 32. `AffiliateCta`
- **`title`**, `subtitle?`, `imageUrl?`, `priceText?`, **`partner`** (enum: registered partners), **`link`**: `LinkTarget`, **`disclosureText`** ("Partner link")
- Events: `affiliate_cta_clicked { partner }`

```
┌────────────────────────────────┐
│ [img] Order ingredients        │
│       ₹340 est. · Blinkit      │
│                  [ Order → ]   │
│ ⓘ Partner link                 │
└────────────────────────────────┘
```

#### 33. `ConsultReferralCard`
- **`headline`** ("शादी का मुहूर्त? विशेषज्ञ से पूछें"), **`partnerName`**, `ratingText?`, **`priceText`** ("₹10/min से"), **`ctaLabel`**, **`link`**: `LinkTarget`, **`disclosureText`**
- Events: `consult_referral_clicked { partner }`

```
┌────────────────────────────────┐
│ 🔮 Headline text               │
│ AstroPartner · ★4.8 · ₹10/min  │
│           [ अभी बात करें → ]     │
│ ⓘ Partner service              │
└────────────────────────────────┘
```

#### 34. `DeepLinkCard`
- **`appName`**, `appIcon?`, **`title`**, `subtitle?`, **`ctaLabel`**, **`link`**: `LinkTarget` (app deep link + Play Store/web fallback)
- Events: `deep_link_opened { appName }`
- v1 workhorse for trains (IRCTC/where-is-my-train handoff) until TIES.

#### 35. `AdSlot`
- **`slotId`**, **`format`**: `nativeCard|banner`, `categoryHint?`
- Rendered by the ad SDK; collapses to zero height on no-fill. Never first child, ≤1 per surface (R1/R3). "Ad" label rendered by the slot itself.

## 8. Event registry

Every event the agent/orchestrator can receive. Analytics taps the same stream.

| Event | Context payload | Emitted by |
|---|---|---|
| `follow_up_selected` | `{ query }` | FollowUpChips |
| `carousel_item_selected` | `{ itemId }` | MediaCarousel |
| `checklist_toggled` | `{ itemId, checked }` | Checklist |
| `source_opened` | `{ url }` | SourceChips |
| `map_opened` | `{ markerId? }` | MapCard |
| `match_details_requested` | `{ matchId }` | CricketMatchSummary |
| `station_selected` | `{ code }` | TrainStatusTimeline |
| `pnr_refresh_requested` | `{ pnr }` | PnrStatusCard |
| `recipe_timer_started` | `{ stepIndex, minutes }` | RecipeCard |
| `upi_pay_initiated` | `{ payee, amount }` | UpiPayButton |
| `affiliate_cta_clicked` | `{ partner }` | AffiliateCta |
| `consult_referral_clicked` | `{ partner }` | ConsultReferralCard |
| `deep_link_opened` | `{ appName }` | DeepLinkCard |
| generic `Button.action` | model-defined | Button |

## 9. Catalog identity & versioning

- `catalogId`: `https://timepass.app/catalogs/core/v1` (bump the path segment on breaking changes; additive prop changes are non-breaking).
- Client announces `supportedCatalogIds`; server selects via `catalogId` in `createSurface`. Catalog is compiled into the app → server must never emit newer-catalog components to older clients (orchestrator keys prompt template on the client's announced version).
- The catalog's `instructions` field carries the composition rules of §5 in model-facing form — this is prompt real estate; keep it under ~600 tokens.

## 10. Flutter mapping (M0 implementation sketch)

```dart
// one CatalogItem per component; schemas generated from this contract
final aqiMeter = CatalogItem(
  name: 'AqiMeter',
  dataSchema: aqiMeterSchema,           // json_schema_builder, generated
  widgetBuilder: (ctx) => AqiMeterWidget(data: AqiMeterData.fromJson(ctx.data)),
);

final coreCatalog = Catalog([...adoptedBasicItems, ...timepassItems]);
final controller = SurfaceController(catalogs: [coreCatalog]);
// server-side: same catalog.json compiled into the Gemini system prompt
```

Repo shape (M0): `app/` (Flutter), `server/` (orchestrator + adapters), `catalog/` (this contract's source-of-truth YAML + generator emitting `catalog.json` + Dart schema files). The generator is the first thing M0 builds — it keeps app, server, and this document from drifting.

## 11. M0 acceptance (traces to product spec §9)

10 scripted queries render correct interactive answers < 4s, covering: cricket live + summary (Notice enforced), panchang (hi + te output), weather + AQI pair, one generic `Markdown` prose answer, one `KeyValueGrid` generic answer, `FollowUpChips` round-trip (chip → new surface), one validator rejection test (payload with off-catalog component must fail closed).

## 12. Open items

1. **v1.0 migration:** v1.0 is RC now, GA expected Q4 2026 (project roadmap). We build on v0.9.1; the catalog generator isolates us — budget a migration sprint when v1.0 lands. Track the evolution guide.
2. **`genui` architecture churn:** the Flutter package is mid-refactor (decoupled core + renderer, granular reactivity — google/a2ui#1877). Pin package versions in M0; revisit at M1.
3. **Numerals in hi/te** (Latin vs Devanagari digits) — user-test at M1.
4. **`ChartCard`** deferred to P1; contract reserved above.
5. **Icon set** (~60 names) frozen during design pass, not before.
