# TimePass — Design System: "Quiet Interface"

**Date:** 2026-07-09 · The style bible for the design pass, modeled on Monogram's product language (teardown evidence in `DESIGN_RESEARCH.md`). Implementation: `app/lib/theme/` (tokens + primitives). Screenshots: `design-*.png` at repo root.

## The idea

**The chrome stays out of the way; the content carries all the color.** Monogram's design bar — white surfaces, one black accent, soft gray tiles with large radii and no borders, semibold sentence-case section headers, gray secondary text, soft-3D imagery doing the emotional work — applied to Indian daily utility. Semantic color appears only where it *means* something: AQI bands, wickets/boundaries, IMD alerts, festival marks. Never in the chrome.

What we took from the Monogram teardown (their homepage + in-app mockups, 2026-07-09):
- White app surface; near-black is the only chrome color (buttons, the big round mic).
- Content tiles: light gray fills (`#F4F4F2`), ~20px radii, **no borders, no strokes**; white cards float on the page with a soft real shadow.
- Section headers: semibold, sentence case ("What you need"); secondary text is small and gray.
- Voice-first: a big black circular mic is the hero control of the input bar.
- Suggestion/follow-up chips: quiet pills, not colored buttons.
- Delight comes from soft-3D object imagery (their ingredient tiles) — we generate ours (see asset pipeline).

## Tokens (source of truth: `app/lib/theme/tp_theme.dart`)

### Color — `TpTokens` (light / dark)

| Token | Light | Dark | Role |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#0F0F10` | page |
| `card` | `#FFFFFF` (soft shadow) | `#1B1B1D` | floating answer card, input pill |
| `tile` | `#F4F4F2` | `#29292C` | inset gray cells: chips, notices, ball dots, sample tiles |
| `bubble` | `#F1F1EF` | `#29292C` | the user's query bubble |
| `ink` / `inkMuted` | `#17171A` / `#88888E` | `#F4F4F5` / `#9A9AA1` | text |
| `action` / `onAction` | `#141416` / white | `#F4F4F5` / near-black | **the one chrome accent**: mic, buttons, checkboxes |
| `link` | `#3B6FD4` | `#8FB0F2` | sources, external taps |
| `signalGreen` / `signalRed` / `warnAmber` | `#2E9E44` / `#E0453A` / `#E8A13D` | lighter variants | **content semantics only** — boundaries/wickets, alerts, LIVE, rahu kalam |
| `shadow` | 8% black | 20% black | card + input-bar elevation |

### Type

- **System stack everywhere** (Roboto + Noto Indic fallbacks): native feel, guaranteed hi/te legibility, zero asset weight. (The earlier Anek bundling was dropped with the Station Board direction; files removed, −4.4 MB.)
- `display(size, weight:)` for large data — scores 22/w700, temps 34/w700, AQI 44/w700; slight negative letterspacing ≥24px.
- `sectionHeader()`: 16/w600 sentence case. `caption()`: 12.5 gray.
- **Indic rules hold**: fixed line-heights (display 1.1–1.3, body 1.5), weight ceiling w700, hierarchy via size/color — never ultra bolds.

### Motion — `TpMotion` (feedback, not decoration)

`enter` 280ms easeOutCubic (fade + 12px rise, `TpEnter`) · `exit` 180ms · `fast` 150ms (control states) · `pulse` 1400ms (LIVE lamp). Waiting is **`ThinkingDots`** — three gray dots breathing in sequence — never a spinner (evidence: conversational/subtle beats artificial indicators; DESIGN_RESEARCH.md §b4). All loops respect `MediaQuery.disableAnimations`.

## Primitives (`app/lib/theme/tp_widgets.dart`)

- `TpCard` — white, radius 20, layered soft shadow, no border; Material inside so ink/ListTiles paint correctly.
- `TpSectionHeader` — sentence-case semibold header, optional trailing widget (e.g. LIVE badge). **Never case-transforms content** (server data, may be Indic).
- `QueryBubble` — gray pill, right-aligned by the caller.
- `ThinkingDots` — the waiting state.
- `PulseDot` / `LiveBadge` — small red lamp + `LIVE`.
- `SampleTile` — empty-state category cell: gray tile + generated 3D object + label + query caption.

## Component rules

- The biggest type on a card is the *data* (score, AQI number, temperature, date); headers stay 16px.
- Callouts are tinted rounded tiles (8–12% alpha of the semantic color, or plain `tile` gray) — no border stripes, no outlines.
- Cricket balls: circles — W red/white, 4|6 green/white, else gray tile.
- AQI meter: six-segment CPCB band scale with an ink marker (encodes the real Indian categories).
- Sources: gray chips with link-blue domain text, 1–2 max (trust research). Follow-ups: gray pills, medium weight.
- Checked checklist items: strikethrough + muted.
- Rahu kalam: soft amber tile; festivals: small amber ◆.

## Shell rules (`app/lib/main.dart`)

- Wordmark: plain `TimePass` w700 — no marks, no color.
- Input bar: one floating white pill (soft shadow) — borderless text field, muted send arrow, and the **black circular mic** as the primary control (red while recording).
- Empty state: "Ask anything." + 2×2 grid of `SampleTile`s (generated soft-3D objects: cricket ball, sun-cloud, diya, leaf) firing trilingual sample queries.
- Errors: red-tinted tile, plain language, Retry.

## Asset pipeline (proven 2026-07-09, both generations)

Soft-3D objects (`assets/art/obj_*.webp`, 16–28 KB each) generated with **`gpt-image-1.5`**, `background: "transparent"`, prompt recipe: *"Soft 3D render in a smooth matte clay-like style, gentle pastel studio lighting … like a polished app-icon object. Subject: X. Isolated on fully transparent background, no backdrop, no ground shadow, no text."* Post-process: strip weak-alpha ambient glow (alpha<48→0, 48–110 attenuated), bbox-crop on alpha>100, LANCZOS to ≤320px, WebP q88. Notes:
- **`gpt-image-2` does not support `background: transparent`** — use 1.5 for isolated objects; 2 for full-bleed art / text-bearing images.
- Models add ambient glow even when told not to — always de-glow programmatically.
- To extend the set style-consistently, pass an approved object as a reference image (edits endpoint), or use the Gemini codelab recipe (`DESIGN_RESEARCH.md` §c).

## Still open (next design increments)

1. **Per-category richness**: more soft-3D objects (train, rupee coin, movie clapper) as hero categories land.
2. **Rive brand moment**: mic listening/speaking state (needs the Rive-on-Impeller spike on a low-end device).
3. **Stagger** entrance across sibling cards in one surface.
4. **Streaming-Markdown shimmer** for the grounded preview.
5. **Low-end device QA** — jank is invisible on flagships; test on a ₹8–12k phone.
6. **On-device dark-mode + Indic type review** on the S23 FE.
