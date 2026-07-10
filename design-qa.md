# Design QA — Monogram-style TimePass shell

- Source visual truth: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/monogram-home-reference.png`
- Implementation screenshot: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/home-final.png`
- Full-view comparison: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/home-comparison.png`
- Focused comparison: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/home-focus-comparison.png`
- Voice state evidence: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/mic-click-state.png`
- Voice motion evidence: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/mic-click-state-2.png`
- Typing state evidence: `/Users/tpavankalyan/Repos/TimePass/output/design-qa/typing-state.png`
- Viewport: 390 × 844
- State: light-mode mobile home, empty history; voice and typing states tested separately

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the native system stack closely matches the source's neo-grotesk typography. Greeting size, bold emphasis, section hierarchy, card labels, and line wrapping are aligned. TimePass copy is intentionally different from Monogram copy.
- Spacing and layout rhythm: 28px content gutters, action spacing, 162px continuation cards, 8px carousel gaps, compact idea rows, card radii, and the three-control bottom dock align with the source. The browser capture omits native OS status and home-indicator insets; Flutter `SafeArea` supplies these on-device.
- Colors and visual tokens: the shell is pure white with near-black ink, neutral gray tiles, and soft black elevation. The source's faint blue-gray lower-page cast was not copied because the user explicitly prioritized a white background.
- Image quality and asset fidelity: all visible content imagery is supplied by the existing production-ready TimePass WebP asset set, with correct aspect ratios and high-quality filtering. Different subjects are intentional product-content substitutions, not placeholders or code-drawn approximations.
- Copy and content: the information architecture matches the source while the actual prompts remain useful for TimePass: morning briefing, cricket, weather/AQI, and panchang.
- Interaction states: menu/language sheet, calendar/panchang shortcut, horizontally scrolling cards, keyboard reveal, text entry, mic activation, listening overlay, animated waveform, and tap-to-stop affordance are present. Two voice frames 280ms apart differ by 2,017 pixels in the waveform crop, confirming motion. Browser console errors and warnings checked: none.

## Comparison history

### Iteration 1

- Earlier finding [P2]: the first coded pass retained a dashboard-like density, wide carousel cards, and an oversized idea row compared with the source.
- Fix: replaced the bordered hero and category rail with the greeting/action composition; reduced continuation cards to 162px, idea cards to 250px, and adopted the source's 8px carousel gap and three-part dock.
- Post-fix evidence: `home-pass1.png` and `home-comparison.png`.

### Iteration 2

- Earlier finding [P2]: after normalizing for the source's OS status bar, the action row and everything below it sat about 16px too low.
- Fix: tightened the greeting-to-action gap, action height, and action-to-section gap without shifting the greeting.
- Post-fix evidence: `home-final.png` and `home-focus-comparison.png`; section baselines and card bounds now align within a few pixels.

### Iteration 3

- Earlier finding [P2]: the active mic waveform exceeded its allocated width and triggered a 10px Flutter overflow warning.
- Fix: increased the waveform slot from 44px to 58px while keeping the pill dimensions unchanged.
- Post-fix evidence: `mic-click-state.png` and `mic-click-state-2.png`; no visual overflow and no browser warnings or errors.

## Open questions

- P3: capture one iPhone and one low-end Android screenshot to tune physical safe-area spacing and verify the listening blur remains smooth under Impeller.
- P3: a Figma motion storyboard would make the waveform-to-transcribing transition easier to tune collaboratively.

## Implementation checklist

- [x] Match the Monogram home composition and white shell.
- [x] Preserve TimePass content and generated-answer behavior.
- [x] Keep typing and primary shortcuts functional.
- [x] Add and verify the focused mic/listening state.
- [x] Check 390 × 844 rendering and browser console.
- [x] Pass analyzer and unit tests.

final result: passed
