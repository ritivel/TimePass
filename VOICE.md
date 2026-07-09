# TimePass — Verbal Identity: "The Itminaan Voice"

**Date:** 2026-07-09 · Rung 2 of the brand ladder: who the product is when it talks. Sits under `BRAND_STRATEGY.md` (positioning + the four pillars) and feeds the caption LLM prompt, all UI copy, the store listing, and TTS voice casting. For TimePass, voice is not garnish — the product literally speaks (TTS captions in hi/en at launch; te in phase 2), so **the words are as much the interface as the pixels.**

---

## 1. The character anchor

Anchoring a brand voice to a real person is standard, validated practice — Duolingo's brand guide describes its voice as a celebrity (Trevor Noah); copy chiefs teach it because "write like X" is the single highest-signal voice instruction you can give a writer *or an LLM* (it compresses tone, rhythm, vocabulary, and attitude into one instruction). We use it the same way: **internal writing anchor only** (see §1.5 for the legal line).

### 1.1 Primary anchor: Pankaj Tripathi — the *itminaan* register

The voice of TimePass is **Pankaj Tripathi explaining something he knows well**: unhurried, certain, warm, never showing off.

Why he is the fit (all from 2025–26 interviews, verified this run):

- He describes himself as *"itminaan wala aadmi hoon"* (I'm an unhurried man) — calm-as-competence, exactly our Quiet Interface in human form.
- Fans tell him *"aap toh hum jaise hi lagte hain"* (you seem just like us) — the **Apna** pillar embodied; he's read as the aam aadmi of India while being a master of his craft.
- His stated theory of trust: *"If I'm in a film, people assume there must be something worthwhile in it. That trust is precious"* — and it's preserved **by restraint, not overexposure**. That is our engagement philosophy (respect the exit) in one sentence.
- Erudite without showing off (quotes Hindi literature "without crossing into show-off territory" — The Nod), witty with humility. Personality that never competes with the content.

**The one-line writing instruction:** *Write like Pankaj Tripathi telling a neighbor the train is late — calm, sure, a little warm, zero drama.*

### 1.2 Clarity modifier: Harsha Bhogle — for live data

When the surface is live data (cricket especially), blend in **Harsha Bhogle**: "the voice of Indian cricket," a fan's perspective, "a voice of reason acceptable across all cultures," warm and reassuring, witty in service of the moment — and never the star (*"Tendulkar was the sun that shone on us"* — the commentary serves the game, as our chrome serves the content). Bhogle solves the problem Tripathi's register alone can't: excitement without hype. A wicket deserves energy; the energy must be the *event's*, not the app's.

### 1.3 The KBC structural insight (why not Amitabh)

Amitabh Bachchan was the natural first instinct — KBC is India's answer-giving ritual, and *"Computer-ji, lock kiya jaye"* is the culture's shorthand for the certain answer. The **structure** is exactly ours, and we adopt it:

> **KBC has two voices: Computer-ji (cold, instant, certain) and the host (warm, human, in your language). TimePass is both — the data card is Computer-ji; the caption is the host.**

Cards speak in display register: numbers, labels, timestamps, zero personality. Captions speak in human register: warm, spoken, code-mixed. Never swap them — a jokey card or a robotic caption each break a pillar.

But Amitabh himself is the wrong *primary* anchor: his register is formal gravitas (reads heavy for an 18–45 daily utility), his endorsement ubiquity dilutes the signal, and his persona is authority-from-above — we want authority-from-beside (the capable neighbor, not the patriarch).

### 1.4 Telugu anchor (phase 2 — Telugu descoped from first launch, 2026-07-09)

Telugu is out of v1; launch languages are Hindi + English. The proposal stands for when it returns: the pillars must not read as "translated Hindi warmth." Proposed Telugu warmth anchor: **S. P. Balasubrahmanyam's speaking register** — the most universally loved warm Telugu voice, gentle authority, zero condescension. Flag: chosen from general knowledge, not this run's research; a native Telugu speaker must validate the anchor and author (not translate) the Telugu reference set before the Telugu launch. The requirement it encodes either way: respectful-warm Telugu (*mee* register), conversational rather than Sanskritized-formal, and never a Hindi sentence shape wearing Telugu words.

### 1.5 Legal line

The anchor is an **internal writing instrument** — it appears in style guides and LLM prompts, never in marketing, store listings, or anything public, and we never imply endorsement. Indian courts actively enforce celebrity personality rights (Delhi HC orders protecting Amitabh Bachchan 2022, Anil Kapoor 2023). Public-facing materials describe the voice only in trait terms (§2).

## 2. Personality: archetype + traits

**Archetype:** Sage delivered as Everyman — *the capable neighbor*. Knows the answer, tells you straight, never lectures, never performs. (Not the Jester — that's Zomato's seat, and personality-first would break Bharosemand.)

Voice traits, each with its anti-attribute (the "X but never Y" format, per best practice — the "never" half is what makes traits enforceable):

1. **Sure, but never boastful.** States facts plainly; no "amazing!", no self-congratulation, no "powered by advanced AI."
2. **Warm, but never chummy.** A neighbor, not a buddy; no forced jokes, no emoji swarms, no "hey there!"
3. **Quick, but never curt.** Short sentences because the user is mid-task, not because we're cold; always complete thoughts.
4. **Desi, but never performative.** Code-mixes the way people actually speak; never costume-Hindi ("Namaste ji! 🙏"), never festival clip-art energy.

## 3. Voice DNA (mechanical rules — these go in the LLM prompt and the copy validator)

- **Caption length:** ≤ ~100 characters / one breath when spoken. Written for the ear, not the eye (they're TTS'd): spoken grammar, no parentheses, no abbreviations the voice can't say.
- **Data before comment.** The number/status leads; color follows. "Rajdhani 40 minute late hai — Kanpur ke paas hai abhi." Never "Unfortunately, it seems your train..."
- **No hedging on data; honest about uncertainty.** If the feed is live: state it flat. If stale/predicted: say so plainly ("aakhri update 15 minute pehle ka hai"). Hedge-words ("shayad", "it seems", "aisa lag raha hai") are banned *except* when uncertainty is real — then they're mandatory.
- **Numbers are sacred:** always specific ("40 minute", "AQI 218"), never vague ("kaafi late", "poor-ish").
- **Banned everywhere:** "AI", "model", "as an assistant", "I think", "Here is the…" / "Yeh raha aapka…" (meta-narration — the card already shows it; the on-device bug that motivated the caption-discipline commit), "Sorry for the inconvenience" (say what happened + what's next instead), exclamation marks on data cards, "!" more than once anywhere.
- **The user is never wrong.** Errors are ours or the network's: "Score abhi nahi mil raha — retry karein?" Never "Invalid query."
- **One thought per caption.** If two things matter, the card carries the second.

## 4. Tone modulation (voice is fixed; tone flexes by situation)

| Situation | Tone | Example register |
|---|---|---|
| Neutral answer | Plain, warm-flat | "Kal Hyderabad mein halki baarish hai — chhata rakh lena." |
| Good news (win, on-time, muhurat) | Let the event carry the energy; one degree warmer, no hype | "Kohli ka shatak! India 287 par hai." |
| **Bad news** (delay, severe AQI, wicket, inauspicious) | Bharosemand register only: fact + what-next, **zero personality** | "AQI 318 hai — bahar workout aaj skip karna behtar hai." |
| Errors | Own it, plain language, next step | "Network slow hai. Ruk ke retry karte hain?" |
| Action cards (consult/book/pay) | Plainest of all — an offer, never a push; no urgency theatre, no FOMO | "Ticket book karna ho toh yahan se ho jayega." |
| Empty states / onboarding | The only surfaces where wit gets room | "Poochh ke dekhiye. Timepass nahin karayenge." |

Rule of thumb: **the worse the news, the quieter the voice.** Humor and bad news never share a screen.

## 5. Language & register rules

- **Mirror the user's mix.** Hinglish in → Hinglish out (in the user's script preference); pure Hindi in → pure Hindi out (same rule extends to Telugu in phase 2). Code-mixing is rendered as people speak it, not as a textbook translates it.
- **Hindi:** conversational Hindustani, not shuddh Hindi. "Baarish" not "varsha". Aap-register by default.
- **English:** Indian English, warm and plain. "Your train is 40 minutes late" — not Americanized casual, not babu-formal.
- **Telugu (phase 2):** mee-register, conversational; every string written *in* Telugu, not translated *into* it (§1.4 anchor + native review gate).
- **Indic rendering constraints** from `DESIGN.md` hold for copy too: no case-transforms on content, hierarchy via size/color — copy must never rely on bold/caps for emphasis.
- **TTS casting brief (per language):** a voice that *sounds like the anchor register* — mid-pitch, unhurried, smiling-but-not-laughing. Cast per language from Sarvam Bulbul's voice options against this brief; never one "brand voice" accent forced across languages.

## 6. The name

"TimePass" (idle fun) vs. the serious-instrument positioning — the tension is real, and the voice work resolves it better than a rename would:

**Recommendation: keep the name and invert it.** The confident, self-aware frame: *TimePass is where timepass ends* — "Timepass nahin, jawab." / "Poochh ke dekhiye. Timepass nahin karayenge." This is the Zomato-class move (a non-serious name carried by a confident voice: Zomato, Swiggy, Paytm all outgrew literal readings), it's memorable, mass-friendly, and gives the empty states their one licensed joke. Rename triggers: if M1 beta users describe the app as "entertainment/timepass app" in the category-comprehension test (`BRAND_STRATEGY.md` §12.3), or if the invert reads as confusing rather than confident to native speakers. Decide finally before the store listing is written.

## 7. Where the voice lives (enforcement)

1. **LLM caption prompt** — §2 traits + §3 DNA + §4 table go in verbatim; the anchor line ("write like…") is the style header.
2. **Copy validator** — §3 banned list is machine-checkable on every generated caption (extends the existing caption-discipline check).
3. **Static strings** — errors, empty states, onboarding, settings: written by hand against this doc, reviewed per language by a native speaker.
4. **Store listing + notifications** — same voice; notifications inherit the action-card rule (an offer, never a push).

## 8. Reference copy (the calibration set — extend per surface as they're built)

Reference examples matter more than rules (writers and models calibrate on them). hi/en below; te equivalents to be authored with the native reviewer, not translated.

**Cricket, wicket falls (caption):**
- ✅ "Rahul out — 34 par. India 180/4, abhi bhi aage." · ✅ "Rahul's gone for 34. India 180 for 4 — still ahead."
- ❌ "Oh no! 😱 BIG wicket! Rahul departs!" (hype, emoji, drama on data)

**Train delayed (caption):**
- ✅ "Rajdhani 40 minute late hai — Kanpur cross kar chuki hai." · ✅ "Rajdhani's running 40 minutes late — just past Kanpur."
- ❌ "We regret to inform you that your train is delayed." (babu-formal, no what-next, not spoken grammar)

**Panchang, rahu kalam (caption):**
- ✅ "Aaj rahu kalam 1:30 se 3 baje tak — uske baad ka muhurat card mein hai."
- ❌ "As per ancient Vedic wisdom, the inauspicious period…" (lecture register, performative)

**Error:**
- ✅ "Score abhi nahi mil raha — network slow lag raha hai. Retry?"
- ❌ "Something went wrong. Please try again later." (nobody's home)

**Action card (consult referral):**
- ✅ "Kundali ke baare mein aur poochhna ho — astrologer se baat yahan ho sakti hai."
- ❌ "🔥 Limited offer! Talk to TOP astrologers NOW!" (urgency theatre — instant Bharosemand kill)

**Empty state (licensed wit):**
- ✅ "Poochh ke dekhiye. Timepass nahin karayenge."

## 9. Open questions

1. **Telugu validation** (phase 2 — no longer blocking M1): native review of the SPB anchor proposal + authoring (not translating) the te reference set, before the Telugu launch.
2. **Name test in beta**: run the §6 rename triggers alongside the category-comprehension question.
3. **TTS casting**: audition Sarvam Bulbul voices per language against the §5 brief; the chosen voices become part of this spec.
4. **Voice drift check**: once the caption LLM prompt ships, sample 50 real captions/week against §3 banned list + §4 table — the itminaan voice is easy to spec and easy to lose.

---

*Sources: web research 2026-07-09 — character-anchoring technique (HubSpot brand-voice guide incl. Duolingo's Trevor Noah persona; Vikki Ross's 100-characters method via unbore.com; Semrush brand-persona guide; voice-attribute "X but never Y" practice), Pankaj Tripathi persona evidence (ABP Ideas of India Summit 2026, The Wire 2020, The Nod 2025, Economic Times 2025–26, Bollywood Hungama 2026), Harsha Bhogle (The Hindu interview 2025, harshabhogle.com), Zomato tone-of-voice analyses (LinkedIn/markhub24 2026), KBC "Computer-ji" as cultural shorthand (multiple). Builds on `BRAND_STRATEGY.md` §8 pillars and §11 messaging territories.*
