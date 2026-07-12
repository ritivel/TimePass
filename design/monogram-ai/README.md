# Monogram AI Teardown For TimePass

Date: 2026-07-09

Sources captured:
- Website: https://www.monogram.ai/
- Launch post: https://www.monogram.ai/blog/introducing-monogram
- Manifesto: https://www.monogram.ai/manifesto
- App Store: https://apps.apple.com/us/app/monogram-ai/id6772350876
- Demo video: `assets/monogram-demo.mp4`
- Contact sheets: `assets/monogram-demo-frames.jpg`, `assets/monogram-appstore-screens.jpg`
- Transcript: `assets/monogram-demo-transcript.txt`

## Core Read

Monogram is not a prettier chat window. It treats every answer as a generated interface: the layout, controls, visuals, and follow-up actions change to fit the question.

The shell stays persistent and sparse:
- top controls: back/close/menu, bookmark/save, calendar or context tools
- bottom controls: plus on the left, a dominant black microphone, keyboard on the right
- surfaces: white or warm-gray, soft elevation, large rounded cards, little or no border
- type: clear semibold titles, gray secondary text, answer-first hierarchy

## Answer Grammar

Observed patterns:
- Direct status queries become a single strong hero card plus follow-up chips.
- "Pick one" queries become a few large recommendation cards with enough detail to decide now.
- Comparisons become visual side-by-side panels, not paragraphs.
- Recipes become ingredient tiles, a stepper, checklists, and modification paths.
- Trips or complex planning start by verifying assumptions through editable UI, then expand into hotels, days, outings, and a plan.
- Maps use the map as the answer surface, with a selected card and actions layered on top.

TimePass translation:
- Cricket, weather, AQI, panchang stay as first-class hero cards.
- Generic answers should choose between `ComparisonTable`, `Checklist`, `KeyValueGrid`, `Markdown`, and follow-up chips by intent.
- Every answer should contain a next step: drill down, compare, modify, plan, save, open source, or ask a narrower follow-up.
- Avoid "here is some text" unless the user asked for prose.

## Voice Interaction

The microphone is the emotional center of the product:
- It is always available in the bottom rail.
- Listening should create a focused state, not just change an icon.
- Background content can blur/fade, while the mic, waveform, and status copy take over.
- Recording ends by tapping the mic again; transcribing becomes a short in-between state.

TimePass implementation target:
- Genda Pop home with a large ask card.
- Persistent bottom dock with plus, text/keyboard, and mic.
- Full-screen voice-focus overlay with blur, listening wave, genda rays, and stop mic.
- Spoken query should produce spoken caption when available.

## Product Feel

TimePass should feel like:
- cheerful daily utility, not enterprise AI
- fast, local, and conversational in Indian everyday language
- visual-first, but not noisy
- warm cream, ink, and genda as brand; teal/coral/blue only when data needs them
- answer surfaces as small useful apps, not chat bubbles
