# Product Spec — "Indian Monogram" (working name: TimePass)

**Version:** 0.1 · 2026-07-08
**Status:** Draft for founder review
**Basis:** Two adversarially-verified deep-research runs (Jul 2026) + targeted source checks. Load-bearing claims cite primary sources; unverified items are flagged.

---

## 1. One-liner

**A visual answer + action engine for Indian daily life.** Ask anything — by voice or text, in Hindi, English, or Telugu — and instead of a wall of chatbot text, get an instantly generated interactive interface: a live cricket scorecard, a train-status card with your PNR, tonight's OTT picks, today's panchang — with the next action (book, pay, order, consult) embedded in the answer itself.

**What Monogram.ai is to chat in the US, we are to Indian daily utility — plus the transaction.**

## 2. Product principles (agreed)

1. **Android first.** Android = ~93% of Indian mobile OS share vs ~6.9% iOS ([StatCounter, Jun 2026](https://gs.statcounter.com/os-market-share/mobile/india)). Built in Flutter → iOS ships later nearly free.
2. **No subscriptions.** IN/SEA converts downloads→paid at 0.7% (vs 2.8% NA), $14 first-year LTV per payer ([RevenueCat 2026](https://www.revenuecat.com/state-of-subscription-apps/)). Monetize via **transactions, affiliate, referral marketplaces, and native ads** — monetization is a *component type* the model can render, not a paywall.
3. **Hindi + English at launch; Telugu in phase 2** (descoped 2026-07-09 to cut v1 surface — one script system and one ASR/TTS pair fewer). Accept messy code-mixed input (Hinglish, any script). Output language is an explicit user setting — Indic preference is strongest on the *output* side (98% consume in Indic languages; only ~19% search in them — [IAMAI-Kantar ICUBE 2024](https://www.iamai.in/sites/default/files/research/Kantar_%20IAMAI%20report_2024_.pdf)). Caution: Telugu was the forcing function that kept the i18n architecture honest (non-Devanagari path) — build templates, line-height tokens, and the renderer script-agnostic anyway so Telugu lands without rework.
4. **Voice in → visual out, with a spoken caption.** Voice input is first-class (~140M voice users, 55% rural). The answer is a visual interface plus a one-line TTS caption ("Rajdhani 40 minute late chal rahi hai — details neeche"). Full spoken-answer mode is an accessibility setting and the phase-2 rural wedge, not the v1 center — full TTS narration would make us a voice assistant (Google's turf) and costs ~4–10× more per query than a caption.
5. **Two-tier coverage, not 100 categories.** The LLM + web search + genUI handles the entire long tail generically from day one. **Six hero categories** get deep structured-data integrations and embedded actions. Frequency is the filter: daily-habit categories build retention; "plan a birthday" is a demo, not a habit.

## 3. Who it's for (v1)

Urban + tier-2 Android users, 18–45, in the Hindi belt (Telugu states AP/Telangana join in phase 2 with the Telugu launch), who already use ChatGPT (India = OpenAI's #2 market, ~100M WAU) but still juggle 6 single-purpose apps for trains, scores, movies, panchang, weather. We replace the *lookup layer* of daily life, not their chat companion.

## 4. Hero categories (v1) — ranked by frequency × data feasibility × monetization

### Tier 1 — launch heroes

| # | Category | Data source & cost | Monetization | Key risk |
|---|----------|-------------------|--------------|----------|
| 1 | **Cricket** | EntitySport $150–450/mo or Roanuz ₹16–60k/mo (verified live pricing; powers MPL, Sportskeeda) | Native ads; fantasy-app referrals | Legal grey zone: [Akuate v. Star (Del HC 2013)](https://indiankanoon.org/doc/66104323/) says match facts can't be owned, but an unresolved SC interim stay imposes a ~15-min-lag status quo for free dissemination. Mitigation below. |
| 2 | **Panchang + festivals + astrology** | Prokerala (free→$99/mo), [VedicAstroAPI](https://vedicastroapi.com/pricing/) ₹1.5–4k/mo (20+ languages incl. **hi/te**), DivineAPI $19+/mo. Daily panchang cacheable per city/day → ~₹0 marginal | **The monetization engine.** AstroTalk: ₹1,176 Cr FY25 revenue (+81%), ₹285 Cr PBT, 1.5M monthly *paying* users, pay-per-consult marketplace — no ads, no subscriptions. We embed consult-referral + devotional-commerce cards | Dominant incumbent (AstroTalk ~85% share) — we refer into the category rather than compete on astrologer supply |
| 3 | **Trains (status/PNR)** | Phased. **v1:** deep-link + best-available public data. **v1.5:** IRCTC **TIES** license — DPIIT startup rate ≈ ₹13–16L first year + ₹0.25+tax/enquiry ([TIES Policy 2025](https://contents.irctc.co.in/en/TIES_Policy.pdf)). Live running status is NOT in TIES (NTES is separate). Booking = separate B2C PSP scheme (₹30–40L, or ride as affiliate of an existing PSP per clause 20.1.2) | Cannot charge users for enquiries (prohibited); booking take capped ₹20/40 per ticket → monetize via **cross-sell** (food-on-train, cab-to-station, hotel affiliate) like ixigo does | Only Google holds TIES today ([official list, Mar 2026](https://contents.irctc.co.in/en/IRCTC%20Authorised%20Principal%20Service%20Providers.pdf)) — approval path unproven for startups; ₹0.30/query data cost is 3–6× our entire AI stack cost |

### Tier 2 — launch, but lighter

| # | Category | Data source & cost | Monetization | Note |
|---|----------|-------------------|--------------|------|
| 4 | **Movies/OTT discovery** | TMDB — free tier is **non-commercial only**; monetized app needs a [commercial agreement](https://www.themoviedb.org/api-terms-of-use) (contact sales; historically startup-affordable). Watch-provider data is JustWatch-sourced, attribution mandatory | Weak today: BookMyShow affiliate via Cuelinks is **paused** (was ₹4.50/sale, EPC ≈ 0). Treat as engagement/retention driver; pursue direct BMS/District partnership | 83% of Indian internet users (732M) consume OTT — highest-frequency category of all |
| 5 | **Weather/AQI + daily prices (gold/fuel)** | ~Free: [IMD API platform](https://api.imd.gov.in/) (city forecast/nowcast/warnings; JWT + whitelisting caveats), CPCB real-time AQI via [data.gov.in](https://www.data.gov.in/resource/real-time-air-quality-index-various-locations) API key | Low direct; native-ad slot; retention/daily-open driver | Zero-cost showcase of genUI (forecast cards, AQI meters). aqicn.org explicitly bans paid-app use — use CPCB/IMD directly |
| 6 | **Recipes** | LLM-native (no API needed); festival tie-ins via panchang calendar | Grocery-delivery affiliate (ingredients→cart), cookware affiliate | Monogram's own demo category; cheap, safe, high-delight |

### Deprioritized (with reasons — revisit in phase 2)

- **Shopping/price comparison:** Amazon PA-API is [closed to new registrants and deprecated May 2026](https://webservices.amazon.com/paapi5/documentation/register-for-pa-api.html) (successor: Creators API, gated by affiliate sales volume); Flipkart affiliate is closed to direct signups (aggregators only); popular-phone commissions are 0–1%. Data access fragile + monetization weakest exactly where query volume is highest (electronics). Do deal-deep-links via Cuelinks/EarnKaro later, not a product-data integration now.
- **Government services/DigiLocker:** partner path exists ([API Setu SOP](https://cf-media.api-setu.in/resources/Partners-SOP.pdf)), but auth-heavy and trust-critical — phase 2.
- **Flights/buses:** affiliate programs exist (redBus/EaseMyTrip terms unverified); train cross-sell covers part of intent — phase 2.
- **Education/exam results:** only 3% self-reported incidence (IAMAI); seasonal spikes — handle via generic tier.

### Cricket legal posture (explicit)

Display free, ad-supported scores with a configurable lag buffer; no paid/premium real-time tier (that's precisely what the SC interim order targets); rely on licensed aggregator feeds (EntitySport/Roanuz) like MPL/Sportskeeda do; get an Indian IP/media-law opinion on current SLP status before launch. This is industry-standard practice, but it's a *managed grey zone*, not a clean right — priced into ranking it #1 anyway because frequency and data cost are unbeatable.

## 5. Language & voice architecture

- **Input:** hi/en in any script, code-mixed (Telugu: phase 2). Pipeline: ASR (voice) → language-ID + transliteration/normalization → intent.
- **ASR:** Sarvam Saarika — ₹30/audio-hour ⇒ ~₹0.05 per 6-sec query ([pricing](https://docs.sarvam.ai/api-reference-docs/pricing)). Fallback/self-host option: AI4Bharat IndicConformer-600M (MIT license, 22 languages, Hindi WER 13.2) when volume justifies GPU ops. Bhashini free tier is PoC-only — not a production plan.
- **TTS caption:** Sarvam Bulbul — ₹15/10k chars ⇒ ~₹0.15 per ~100-char caption. Voices per output language.
- **Output language:** explicit user setting (hi/en; te added in phase 2), independent of input language. Component templates + TTS voices localized in both from day one. With Telugu deferred, the non-Devanagari discipline it enforced must be kept by policy: no hardcoded script assumptions in templates, tokens, or renderer (per-script line-height tokens stay in the theme).

## 6. Generative-UI architecture

**Recommendation: Google A2UI (open standard) + our own Flutter component catalog. Not Thesys C1.**

- A2UI (v0.9→1.0 RC, Apache-2.0) has an official Flutter renderer and renders only from a **pre-approved component catalog** — exactly what we need: deterministic, brandable, safe, and *our monetization components are just catalog entries the model can compose*.
- Thesys C1 is a fast start (drop-in OpenAI-compatible API) but React-rendered (wrapper needed in Flutter), $0.01/page ≈ ₹0.83/answer — that alone is ~10× our LLM cost and breaks India unit economics at scale, plus small-vendor dependency. Acceptable for a throwaway web prototype only.
- **LLM:** Gemini 2.5 Flash-Lite for genUI composition — ~₹0.05 per answer (~2K in + 1K out tokens at $0.10/$0.40 per 1M, [pricing](https://ai.google.dev/gemini-api/docs/pricing)). Evaluate Sarvam-30B (₹2.5/₹10 per 1M) as Indic-answer alternative. Batch API (half price) pre-generates daily cacheables: panchang, horoscopes, weather summaries, price tickers.

**Component catalog v1 (~25 components):** scorecard-live, scorecard-summary, train-status-timeline, pnr-card, comparison-table, media-carousel (posters + where-to-watch), panchang-card, muhurat-list, horoscope-card, weather-forecast-strip, aqi-meter, price-ticker, recipe-steps, ingredient-list, checklist, map-card, generic-list/detail/chart, and the **action components**: upi-pay, affiliate-cta, consult-referral, deep-link-card, ad-native-slot.

**Flow:** query → (ASR) → normalize → intent router → hero-category tool call (structured data) OR generic web-search tool → LLM composes A2UI component tree + one-line caption → Flutter renders + TTS caption plays → interactions (taps, follow-ups) loop back as context.

**Server-side:** thin orchestrator (tool registry per hero category, response cache, per-category data adapters). Cache aggressively: panchang/horoscope/weather are per-city-per-day; cricket scorecards per-match-per-N-seconds shared across all users — marginal data cost per query trends to ~0 on hits.

## 7. Unit economics (per-query, INR)

| Component | Text query | Voice query |
|---|---|---|
| ASR (6s, Sarvam) | — | ₹0.05 |
| LLM genUI (Flash-Lite) | ₹0.05 | ₹0.05 |
| TTS caption (~100 chars) | — | ₹0.15 |
| Category data (amortized, cached) | ~₹0.00–0.05 | ~₹0.00–0.05 |
| **Total** | **~₹0.10** | **~₹0.30** |
| Trains via TIES (uncacheable per-user PNR) | +₹0.30 | +₹0.30 |

Revenue side: India ad eCPMs are the weakest of major markets (banner worst; rewarded video the only resilient format — Bidlogic Q2'25), so native-ad slots are a floor, not the model. The model is **actions**: one astrology consult referral, train-journey cross-sell, or grocery cart is worth hundreds of info-queries. Design metric: **≥1 monetizable action surface per session**, not per query. Pure-info queries at ₹0.10 are an acceptable loss-leader; voice+trains at ₹0.60 is why TIES comes *after* traction, not before.

## 8. Moat & competitive posture

- **GenUI is not the moat** — Google shipped it in Gemini/Search AI Mode (US-only today; [Google Research, Nov 2025](https://research.google/blog/generative-ui-a-rich-custom-visual-interactive-user-experience-for-any-prompt/)), and Google+Jio already give 500M Jio users a free premium Gemini bundle. The window is real but unknown.
- **The moat is boring and Indian:** licensed data plumbing (TIES agreement, cricket feeds, TMDB commercial deal, IMD/CPCB), action rails (UPI deep-links, affiliate/referral contracts, consult marketplace deals), and hi/te-quality voice UX. Every one of these is a bilateral contract or government process a US/global player won't prioritize — the Krutrim lesson inverted: don't build models (Krutrim died doing that), build the layer models can't have.
- **Positioning vs ChatGPT:** not "better AI," but "the app where the answer is the app" — faster than chat for lookups, and it *finishes the job* (pay/book/order).

## 9. v1 scope & milestones

- **M0 (weeks 1–3) — Vertical slice:** Flutter app, A2UI renderer, 8 components, cricket + panchang + weather via real APIs, hi/en text input, script-agnostic renderer verified (no Devanagari-only assumptions). Success: 10 scripted queries render correct interactive answers < 4s.
- **M1 (weeks 4–8) — Private beta:** voice in + TTS caption, all 6 hero categories (trains via deep-links), generic long-tail tier, output-language setting, basic analytics. 100 users in the Hindi belt. Success: D7 retention > 20%, ≥3 sessions/week/user.
- **M2 (weeks 9–14) — Monetization + launch prep:** consult-referral + affiliate + UPI deep-link components live, native-ad slot, TIES application filed in parallel (DPIIT recognition first), cricket legal opinion obtained, TMDB commercial agreement signed. Success: ≥1 action per 3 sessions; revenue per DAU measurable.
- **North-star metric:** weekly answer-sessions per user with an action taken.

## 10. Legal/licensing & diligence register (do before/at M2)

| Item | Action | Status |
|---|---|---|
| DPIIT startup recognition | Apply immediately — unlocks TIES 50% concession | ☐ |
| IRCTC TIES | File application; validate startup approval path (only Google listed today); clarify NTES live-status access | ☐ |
| Cricket SC stay | Indian IP-counsel opinion on Star v. Akuate SLP status + safe lag/monetization posture | ☐ |
| TMDB commercial agreement | Email sales@themoviedb.org (required for any monetized app) | ☐ |
| Sports feed contract | EntitySport vs Roanuz — verify IPL coverage tier + indemnity clauses | ☐ |
| BMS/District partnership | Direct BD conversation (affiliate channel is dead) | ☐ |
| Astro consult partner | AstroTalk affiliate/API or #2 player deal for consult-referral card | ☐ |
| IMD API access | Register on api.imd.gov.in; confirm commercial-use + whitelisting terms | ☐ |
| DPDP Act compliance | Voice recordings + Google Sign-In data — privacy policy + consent flows | ☐ |

## 11. Open questions

1. TIES in practice: will IRCTC approve a non-Google startup, and on what timeline? (Determines whether trains stays hero or becomes deep-link-only for longer.)
2. Gemini genUI India timeline — the single biggest external clock on this plan.
3. Real ad eCPMs for our surface (native cards in a utility answer app) — need a live test, published benchmarks are format-generic.
4. Whether a consult-referral deal with AstroTalk is gettable at meaningful rev-share, or whether a smaller astrology marketplace partner converts better.

---

*Sources: verified findings from deep-research runs wf_646cb95c (market) and wf_9a0fc95d (categories), plus primary-source checks on TMDB/JustWatch, Prokerala/VedicAstroAPI/DivineAPI, IMD/CPCB, and API Setu — July 8, 2026. Full evidence trails in session task outputs.*
