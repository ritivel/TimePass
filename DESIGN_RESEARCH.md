# TimePass — Design Research (for the design pass)

**Date:** 2026-07-09 · Deep-research run: 110 agents, 27 sources fetched, 25 top claims adversarially verified (23 confirmed, 2 refuted). Companion docs: `PRODUCT_SPEC.md`, `COMPONENT_CATALOG.md`, `PROGRESS.md`.

## TL;DR

Monogram's careers page says the quiet part out loud: **motion craft applied to a small set of polished primitives is the product**. That is exactly our catalog architecture — so the design pass is not "make it pretty", it's the same leverage play Monogram staffs 30% of its openings for. The evidence-ranked priorities: (1) polish the 19 catalog components once, (2) build a motion-token system (100–500ms, feedback-not-decoration), (3) brand the waiting states — latency perception is a first-order design problem, (4) show 1–2 *real* sources (more citations ≠ more trust), (5) vibrant + dense-with-hierarchy for the Indian mass market, not sparse Western minimalism, (6) fixed per-script line-heights and no heavy bolds for Devanagari/Telugu. Asset pipeline: `gpt-image-2` (verified on our key) for text-bearing art, icons (transparent bg), and style-locked illustration sets; Gemini Nano Banana 2 for cheap volume. Motion stack: plain Flutter + Impeller for micro-interactions, Rive for a few hero brand moments, **avoid Lottie on Android** (verified GPU-bandwidth jank on exactly our target device class).

---

## (a) What Monogram values in design — from careers + product evidence

All verified verbatim on live primary pages 2026-07-09 ([monogram.ai/hiring](https://www.monogram.ai/hiring), [Ashby JDs](https://jobs.ashbyhq.com/monogram/3fa03b4f-ec86-48f5-a247-2c4aa51418e6), [launch blog](https://www.monogram.ai/blog/introducing-monogram), homepage).

1. **Motion is the differentiating craft, not the garnish.** The Design Engineer role exists to "invent and build state of the art transitions and animations to bring the app to life" — described as "what makes Monogram's User Interface feel so special." They screen for "pixel-perfect execution, motion design, and high-fidelity animations." 2 of 7 open roles (~30% of open headcount) are design roles.
2. **Design leverage concentrated in primitives.** The Designer role designs "the building blocks that power Monogram's AI-native models" and "the core navigation flow and interaction framework" — designers craft blocks + motion, the model composes layouts. This is structurally our catalog plan (one polished implementation per component, every answer inherits it). Caveat: Monogram also trains a UI-generation model, so it's not a pure static catalog.
3. **The stated bar:** interfaces consistent "as if a single designer crafted entire flows, hundreds of thousands of different interfaces... 'on the fly', in just 1 or 2 seconds" (self-reported marketing, not benchmarked — but it's the bar they market on).
4. **Taste over process.** Hiring filter: "You think you have good taste!" and "prototyping quickly in high definition, rather than putting together a deck."
5. **Native-stack motion.** Swift/SwiftUI/UIKit required, CoreAnimation + Metal bonus points; iOS-only (App Store id6772350876, no Play Store). Their motion bar is platform-native GPU-level; we approximate it in Flutter via Impeller/shaders/Rive — see (d).
6. **Bespoke style-locked illustration set.** Homepage showcases one custom soft-3D pastel illustration per scenario (recipe, movie, birthday, restaurant, EV comparison), uniform 248×248, served from a dedicated `/illustrations/` directory. Per-scenario art, not stock icons. (2-1 vote: bespoke + consistent is verified; whether hand-made or AI-generated is unknown — which is itself encouraging for our pipeline.)
7. **Same bet as ours:** "AI deserves a better interface than chat: one that is visual, interactive, and more intuitive"; voice + genUI framed as the GUI-vs-command-line transition. Differences: US market, iOS, free-form generation, no transactions.

**Read-across for TimePass:** our moat-relevant asset isn't more components, it's the *feel* of the 19 we have. Budget the design pass like Monogram budgets headcount: roughly a third of the effort on motion/transitions alone.

## (b) Design principles, ranked for the M0→M1 design pass

Ranked by strength of evidence × leverage for us.

1. **Polish primitives once; the LLM composes designed-feeling answers for free.** (Monogram model above; also arXiv [2604.09577](https://arxiv.org/html/2604.09577v1): injecting a detailed style section into the prompt made the model adapt *all* elements to the style — for us the equivalent is Flutter theme tokens, enforced deterministically rather than prompted.)
2. **Gen-UI is worth polishing at all:** humans preferred generated-UI answers over markdown 82.8% of the time (ELO 1736 vs 1438) and over plain text 97% ([Google research](https://research.google/blog/generative-ui-a-rich-custom-visual-interactive-user-experience-for-any-prompt/), arXiv 2604.09577). Google's shipped implementation is Gemini 3 Pro + tools + crafted system instructions + **post-processing** — quality comes from scaffolding, which is what our validator/normalizer already is.
3. **Motion tokens, feedback-first.** NN/g: animation works "with a light touch — primarily as a tool for providing users with easily noticeable, smooth feedback", not decoration. Durations: **100–500ms** for most UI motion; entrances slightly longer than exits (~300ms in / ~200–250ms out) ([NN/g duration](https://www.nngroup.com/articles/animation-duration/)). Encode as theme tokens: `motion.fast=150ms, motion.base=250ms, motion.enter=300ms, motion.exit=200ms`, one or two curves.
4. **Latency perception is a design surface.** 54-participant CUI '25 study ([arXiv 2507.22352](https://arxiv.org/pdf/2507.22352)): >4s latency degrades experience; 1.5s agents were most-liked 57% of the time, 6.5s agents most-disliked 61%; **natural conversational fillers improved perceived response time while spinner-style indicators did not**. Every major AI product ships a *branded* thinking animation (ChatGPT pulsing dot, Claude pulsing star, Gemini rotating star, Perplexity book-pages). We already stream grounded text at ~2.7s and captions at ~1.25s p50 — the design pass should add (i) a branded thinking/listening mark, (ii) spoken-caption-as-filler for voice queries (we get this almost free via TTS), (iii) skeletons that prevent reflow, upgrading in place (our current behavior — keep it).
5. **Trust = one or two real sources, not citation count.** AAAI-25 RCT, N=303 ([arXiv 2501.01303](https://arxiv.org/pdf/2501.01303)): citation presence significantly raises trust; five citations were NOT more trusted than one; and when users *checked* random citations, trust collapsed to zero-citation levels. Design: 1–2 SourceChips max, and the freshness gate must guarantee they actually support the answer. Bonus finding: trust correlates slightly negatively with answer complexity — plain-language captions help trust, not just TTS.
6. **Indian mass-market aesthetic: vibrant, purposefully dense, strong hierarchy.** Google Next Billion Users field research ([Connectivity, culture and credit](https://design.google/library/connectivity-culture-and-credit)): users rejected minimalist UIs ("I don't like the way it looks") because "local visuals are more vibrant and dense"; corroborated by 2023–25 India practitioner analyses. Caveats: 2017 qualitative work (2-1 vote), Tier-1 users tolerate minimalism; the target is clarity-through-visible-density (labels visible, actions surfaced), not clutter.
7. **Three pillars of delight — motion alone is "surface delight."** Norman via [NN/g](https://www.nngroup.com/articles/pillars-user-delight/): lasting delight needs visceral (aesthetics) + behavioral (speed/usability) + reflective (meaning/identity — for us: sources, local cultural relevance, "it finishes the job") simultaneously. A checklist for each component: does it look good, respond instantly, and mean something?
8. **Indic typography rules** (practitioner case study, 9 Indian scripts, [source](https://medium.com/design-bootcamp/learnings-from-designing-for-multiple-indian-languages-1cc2425c0b33); Google Design [Indian type](https://design.google/library/new-wave-indian-type-design)):
   - `auto` line-height varies wildly across scripts — lock explicit line-height tokens tested against en/hi/te samples.
   - Heavy/bold weights blur Indic letterforms — build hierarchy with size/color/space, not bold, for Devanagari/Telugu.
   - Devanagari has far fewer good fonts than Latin; **Mukta** is proven at mass-market scale (major Hindi newspapers) but covers Devanagari/Gujarati/Gurmukhi/Tamil/Latin — **not Telugu**. Evaluate Noto Sans (Devanagari+Telugu, guaranteed coverage) vs Mukta+a paired Telugu face. Test on-device at small sizes before committing.
9. **Asset weight is a design constraint.** Prepaid-data reality (Google NBU) means generated imagery must ship compressed (WebP), cached, and degrade gracefully offline. (Note: the oft-quoted "$40–60 / 512MB device" figure was **refuted** in verification as outdated pre-Jio data — set the budget empirically: test on one real low-end device, not specs folklore.)
10. **What NOT to copy:** Google's maximalist gen-UI (full HTML/CSS/JS per answer) takes "a minute or more" and Nielsen calls the output "cheap, disposable UI." Our fixed-catalog approach trades expressiveness for speed and consistency — the evidence above says that's the right trade at our latency budget.

## (c) Asset-generation pipeline (both keys verified live in SSM 2026-07-09)

**Models available to us today:**

| Provider | Model | Use | Notes |
|---|---|---|---|
| OpenAI (`/shared/openai-api-key`) | **`gpt-image-2`** (`gpt-image-2-2026-04-21`) | primary for brand/illustration/icon sets, anything with text | Released 2026-04-21; #1 across Image Arena (+242 in text-to-image); multilingual text rendering incl. South Asian scripts (launch blog demos); `background: "transparent"` for icons; arbitrary resolutions (multiples of 16, ratio ≤3:1, ≤3840px edge); mask-based edits; up to 8 style-consistent images per prompt; reasoning/thinking mode can self-check outputs. ~$0.006 / $0.053 / $0.211 per 1024² at low/med/high. ([API guide](https://developers.openai.com/api/docs/guides/image-generation), [announcement](https://community.openai.com/t/introducing-gpt-image-2-available-today-in-the-api-and-codex/1379479)) |
| OpenAI | `gpt-image-1-mini` / `gpt-image-2` quality=low | cheap batch exploration | OpenAI's own guidance: quality=low is "a strong fit for high-volume generation and experimentation" |
| Gemini (`/shared/gemini-api-key`) | **Nano Banana 2** (`gemini-3.1-flash-image`), **Pro** (`gemini-3-pro-image`) | volume generation; search-grounded imagery | `gemini-2.5-flash-image` is legacy — don't use. Google's official [consistent-imagery codelab](https://codelabs.developers.google.com/gemini-consistent-imagery-notebook): style consistency with **no fine-tuning** via reference images, character sheets, descriptive/imperative prompts, and an "asset graph" over the library. (Exact reference-image count limits were refuted in verification — check docs when implementing.) |
| Gemini | `imagen-4.0-*` | pure text-to-image alternative | separate dedicated line; fast/ultra tiers |

**Recommended pipeline (build-time, human-curated — assets ship in the APK/catalog, nothing generated at runtime):**

1. **Define the style bible first** (the design pass output): palette, illustration style description (e.g. Monogram uses soft-3D pastel), do/don't list. Written as a reusable prompt block + 3–5 approved reference images.
2. **Generate the master set with `gpt-image-2`**: one illustration per hero category / empty state / error state / onboarding moment, batch of 8 per concept, thinking mode on for consistency, transparent-background PNG for icon-like assets. Its text rendering also makes it the tool for any in-image Devanagari/Telugu.
3. **Style-lock and extend with the codelab recipe** (either provider): approved image → reference image → generate siblings. Nano Banana 2 for cheap iterations/variants; escalate to `gpt-image-2` high or Nano Banana Pro for finals.
4. **Vector where it's UI, raster where it's art.** Image models emit raster. UI icons: keep a real icon font / SVG set (crisp at any DPI, tiny); use generated art only for illustrations, empty states, category heroes. Ship raster as WebP at 2–3 densities; consider tracing flat outputs to SVG for the few that must scale.
5. **Licensing:** OpenAI's terms assign output ownership to the user with commercial use permitted; Google's generative terms similarly permit commercial use (Gemini images carry SynthID watermarks). Re-verify both providers' current terms at ship time — this run did not adversarially verify licensing text.

## (d) Flutter motion stack — recommendation + performance caveats

Evidence (extracted this run; not all adversarially verified — flagged where primary):

- **Impeller is the default renderer and the official fix for first-run shader jank** (Flutter docs, updated 2026-05-05, Flutter 3.44 — primary). No SkSL warmup needed.
- **Lottie janks on Android mid/low-end** ([flutter#148472](https://github.com/flutter/flutter/issues/148472) — primary, incl. Flutter engine engineer diagnosis): GPU **memory-bandwidth** bottleneck, not CPU; same files play fine in Telegram native and web players; **invisible on flagships** (Pixel 4 showed no difference). Exactly our target device class. dotLottie/ThorVG is improving (claimed 80% faster on iOS) but the Android/Flutter path is the risk.
- **Rive**: state machines + **data binding** (bind strings/numbers/enums/images into the animation at runtime — i.e., parameterizable, data-driven motion, the same trick as our dataModel bindings); dual renderer (`Factory.rive`/`Factory.flutter`); `RivePanel` shared-texture mode for many instances. Caveats: ships as `0.14.0-dev.x` (declared production-ready) with native libs via `rive_native`, and Rive itself warns of possible Impeller discrepancies (test `--no-enable-impeller` if artifacts appear).
- **NN/g motion durations** (see (b)3) supply the token values.

**Recommendation, in order:**

1. **Plain Flutter animations + `flutter_animate` for all catalog micro-interactions** — card entrances (staggered, ~300ms in/200ms out), chip presses, value-change ticks, skeleton→content crossfades. Cheapest, no dependencies, Impeller-safe, fully theme-tokenized.
2. **One Impeller fragment shader** for the streaming-text shimmer / LIVE-data pulse — trivially cheap on GPU and very "Monogram."
3. **Rive for ≤3 hero brand moments**: the branded thinking/listening/speaking mark (voice states), the app's identity animation, maybe live-cricket pulse. Data binding lets the server's dataModel drive them. Budget a spike to validate Rive-on-Impeller on a low-end device first.
4. **No Lottie on core answer surfaces** (Android bandwidth jank). Acceptable only for rare, non-core decorative moments if ever.
5. **Test on a real low-end phone, not the S23 FE** — the Pixel 4 lesson: this class of jank does not reproduce on flagships. Acquire/borrow a ₹8–12k device for the design-pass QA loop.

**Micro-interaction inventory to design (maps to existing surfaces):** streamed Markdown preview shimmer → composed-surface in-place upgrade transition; skeleton entrance (no reflow); staggered component entrance; caption 🔊 speaking indicator; mic listening/recording states; LIVE badge pulse + row-update flash (cricket 8s refresh); follow-up chip press/commit; source-chip tap; error-card retry.

---

## Refuted during verification (do not reuse)

- "$40–60 / 512MB emerging-market device" budget — outdated (0-3 vote).
- Nano Banana 2 "10 object + 4 character + 3 style reference images" limits — unconfirmed (1-2); check live docs.

## Open questions

- Exact OpenAI/Google licensing language for shipping generated assets commercially (verify at ship time).
- Rive 0.14-dev stability on Impeller on low-end Android (needs the spike in (d)3).
- Telugu typeface choice (Noto Sans Telugu vs alternatives) — needs on-device legibility test.
- A teardown of Monogram's actual shipped app (App Store id6772350876) — marketing pages only were verified; someone with a US iOS device could record real transitions.
