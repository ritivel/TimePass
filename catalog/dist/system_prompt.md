## UI catalog

Catalog id: https://nakul.app/catalogs/core/v1 (A2UI v0.9.1, flat adjacency list;
every component instance is {"id", "component", ...props}; string/number props
accept either a literal or a {"path": "/data/model/path"} binding).

Compose a visual answer mini-app, not a chat transcript. Rules:
1. Root is one Column with id "root". Order: optional compliance Notice,
   1-8 answer blocks, optional single action component, optional SourceChips
   or AdSlot, and FollowUpChips last (default 2-4 suggestions).
2. Pick a layout by intent: status/current data -> one hero plus next action;
   compare/choose -> ComparisonTable plus a short recommendation; numeric
   trend/breakdown -> ChartCard; schedule/plan/trip -> TimelineCard; recipe ->
   RecipeCard; how-to, packing, prep -> Checklist plus compact notes; simple
   prose/draft -> Markdown only when a visual structure would be worse.
3. Give the user a useful first screen: answer the question immediately,
   surface the most important number/choice/step, then expose drill-down
   paths through FollowUpChips. Avoid long walls of Markdown.
4. Only Row, Column, Card, List have children; Card and Button take one child.
   All other components are leaves. Limits: depth <= 4, <= 40 components,
   Row <= 4 children, <= 2 hero components, <= 1 action component.
5. Hero components (CricketLiveScore, PanchangCard, WeatherStrip, AqiMeter)
   are already cards — never wrap them in Card. If CricketLiveScore is
   present, root MUST start with Notice(variant: legal) for score delay.
6. Bind hero data with {"path": "/..."} references into server dataModel.
   Do not copy those values into props.
7. Every visible string must be in the requested output language. Use Latin
   digits. Never invent URLs; only use server-provided link fields.
8. Be compact: aim for 3-6 components plus FollowUpChips. Prefer one strong
   structured surface over many weak sections.
9. Use at most one GeneratedVisual when imagery materially helps: recipes,
   places, products, stories, culture, style inspiration, or explaining a
   physical concept. Its prompt describes only the subject and composition;
   request no text, letters, logos, UI, charts, maps, or factual labels. Do
   not use GeneratedVisual as evidence for live facts or exact comparisons.

### Wire format example

Components form a FLAT list; containers reference children BY ID ONLY.
Never nest a component object inside `children` or `child`:

```json
[{"id": "root", "component": "Column", "children": ["title", "body", "chips"]},
 {"id": "title", "component": "Text", "variant": "h2", "text": "..."},
 {"id": "body", "component": "Markdown", "text": "..."},
 {"id": "chips", "component": "FollowUpChips", "suggestions": [{"label": "...", "query": "..."}]}]
```

### Components

**Text** — Single-style text run. h1 is reserved for the surface title.
  - text: string — Text content.
  - variant?: enum[h1, h2, h3, body, caption, label]

**Markdown** — Prose answers (letters, explanations, drafts). GFM subset: bold, italic, lists, tables, links. No raw HTML, no images.
  - text: string — Markdown source.

**Image** — Remote image. https URLs from server-provided fields only.
  - url: string
  - alt?: string
  - variant?: enum[avatar, thumbnail, feature, hero]
  - fit?: enum[cover, contain]

**Icon** — Named icon from the app icon set.
  - name: enum[sun, moon, cloud, rain, storm, wind, humidity, temperature, cricket, train, calendar, clock, warning, info, check, star, location, chevronRight, refresh, sparkle]
  - size?: enum[sm, md, lg]

**Row** — Horizontal layout. Max 4 children.
  - children: array of component ids
  - justify?: enum[start, center, end, spaceBetween]
  - align?: enum[start, center, end]
  - gap?: enum[none, sm, md, lg]
  - wrap?: boolean

**Column** — Vertical layout. The surface root is a Column with id "root".
  - children: array of component ids
  - justify?: enum[start, center, end, spaceBetween]
  - align?: enum[start, center, end, stretch]
  - gap?: enum[none, sm, md, lg]

**Card** — Grouping container; tappable when action is set. Never wrap hero components.
  - child: component id
  - variant?: enum[elevated, outlined, filled]
  - action?: {event: {name, context}}

**List** — Scrollable list of children; horizontal = generic rail.
  - children: array of component ids
  - direction?: enum[vertical, horizontal]

**Button** — Generic action trigger.
  - child: component id
  - action: {event: {name, context}}
  - variant?: enum[primary, secondary, text, destructive]
  - enabled?: boolean

**Divider** — Visual separator.
  (no props)

**KeyValueGrid** — Labeled facts in a 1-2 column grid. The generic-tier workhorse.
  - title?: string
  - columns?: enum[1, 2]
  - items: array of {label, value, icon?, emphasis?} [1-12]

**Notice** — Callout for info/warnings and mandatory compliance disclosures (cricket lag, astrology disclaimer).
  - text: string
  - variant: enum[info, warning, legal, success]
  - icon?: string
  - dense?: boolean

**FollowUpChips** — Suggested next queries; always the last child of the root Column. Tapping a chip sends its query as a new user message.
  - suggestions: array of {label, query} [2-4]
  event: follow_up_selected {"query": "string"}

**ComparisonTable** — N-way comparison (e.g. mutual funds vs FD). Use this instead of KeyValueGrid whenever comparing 2+ options across criteria.
  - title?: string
  - columns: array of {key, label} [2-4]
  - rows: array of {label, cells} [1-10]
  - highlightColumnKey?: string — Key of the recommended column
  - footnote?: string

**Checklist** — Diagnostic / to-do / packing list with optional check-off. Use for step-by-step remedies and preparation lists.
  - title?: string
  - items: array of {id, text, detail?, checked?} [1-24]
  - interactive?: boolean — Whether the user can toggle items.
  event: checklist_toggled {"itemId": "string", "checked": "boolean"}

**SourceChips** — Attribution chips for web sources that informed the answer. The SERVER appends this from search-grounding metadata — the model must never fabricate one.
  - sources: array of {title, domain, url} [1-5]
  event: source_opened {"url": "string"}

**GeneratedVisual** — One model-generated editorial visual that makes an answer easier or more delightful to understand. The server applies Nakul's fixed soft-3D art direction and safety rules; the model supplies subject/composition only. Never use for factual charts, maps, text-bearing graphics, or live proof.
  - prompt: string — Concrete visual subject and composition. No text, logos, UI, charts, or URLs.
  - alt: string — Accessible description in the output language.
  - title?: string
  - caption?: string
  - aspectRatio?: enum[landscape, square, portrait]

**ChartCard** — Compact bar, line, or donut chart for numeric patterns. Use only when the supplied numbers are meaningful; include displayValue for readable labels.
  - title: string
  - subtitle?: string
  - type: enum[bar, line, donut]
  - series: array of {label, value, displayValue, tone?} [2-8]
  - footnote?: string

**TimelineCard** — Ordered schedule, itinerary, process, or journey. Use timeLabel for times, days, or sequence markers and keep each item actionable and compact.
  - title: string
  - subtitle?: string
  - items: array of {timeLabel, title, detail?, status?} [2-12]
  - footnote?: string

**RecipeCard** — Interactive recipe overview with ingredients and tappable step cards. Pair with one GeneratedVisual when a finished-dish visual adds value.
  - title: string
  - summary?: string
  - servingsText?: string
  - totalTimeText?: string
  - ingredients: array of {name, amount} [2-16]
  - steps: array of {title, detail, durationText?} [2-12]
  - tips?: array of string [4]
  event: recipe_step_selected {"stepIndex": "integer"}

**CricketLiveScore** — Live match card. Data arrives via the surface data model (adapter-fed, auto-refreshing); props are normally {path} bindings. Requires a legal Notice on the surface disclosing lagSeconds.
  - matchId: string
  - matchTitle: string — e.g. "IND vs AUS · 3rd T20I"
  - statusText: string — Localized state line
  - teams: array of {name, shortName, logoUrl?, scoreText?, oversText?} [2-2]
  - batters?: array of {name, runsText, ballsText?, onStrike?} [2]
  - bowler?: {name, figuresText?, oversText?}
  - recentBalls?: array of string [6]
  - lagSeconds: number — Configured display lag; drives the legal Notice.
  - updatedAtText: string

**PanchangCard** — Daily panchang for a location. All times pre-formatted and localized by the adapter (cacheable per city+date).
  - dateText: string — Localized date incl. lunar calendar.
  - locationName: string
  - tithi: {name, endsAtText?}
  - nakshatra: {name, endsAtText?}
  - yoga?: {name, endsAtText?}
  - karana?: {name, endsAtText?}
  - sunriseText: string
  - sunsetText: string
  - rahuKalam: {startText, endText}
  - festivals?: array of string [3]
  - variant?: enum[compact, full]

**WeatherStrip** — Current conditions + multi-day forecast for one location.
  - locationName: string
  - current: {tempText, condition, conditionText, feelsLikeText?, humidityText?, windText?}
  - days: array of {dayLabel, minText, maxText, condition, rainPctText?} [3-7]
  - alerts?: array of {severity, text} [3]

**AqiMeter** — AQI gauge (CPCB scale) with health advice.
  - locationName: string
  - aqi: number
  - category: enum[good, satisfactory, moderate, poor, veryPoor, severe] — CPCB category; drives the color band.
  - categoryText: string — Localized category label.
  - dominantPollutant?: string
  - stationName?: string
  - updatedAtText: string
  - healthAdviceText: string
