"""Generic-tier orchestration: provider-agnostic compose pipeline.

Providers (llm/gemini.py, ...) stream raw text + grounding sources; this
module owns everything else — prompt assembly (with conversation history),
progressive NDJSON framing (placeholder → early caption → validated final
surface), lenient parsing, shape normalization, the validation-feedback
repair retry, server-side SourceChips attachment, and the offline mock.

Select a provider with LLM_PROVIDER (default "gemini"). An unconfigured
provider degrades to the mock, so the server always answers.
"""

from __future__ import annotations

import json
import logging
import os
import re
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

from .. import a2ui
from ..a2ui import flatten_components
from ..adapters import aqi, cricket, panchang, weather
from ..validator import SurfaceValidationError, catalog_id, known_props, validate_surface
from .base import Chunk, Final, Provider, Source, Turn
from .gemini import GeminiProvider

log = logging.getLogger(__name__)

PROMPT_PATH = Path(
    os.environ.get(
        "NAKUL_SYSTEM_PROMPT_PATH",
        Path(__file__).resolve().parents[4] / "catalog" / "dist" / "system_prompt.md",
    )
)

_PROVIDERS: dict[str, Provider] = {"gemini": GeminiProvider()}

_LANG_NAME = {"en": "English", "hi": "Hindi", "te": "Telugu"}

_OUTPUT_CONTRACT = """
Respond with ONLY a JSON object — no prose, no markdown code fences — of the form:
{"caption": "<one spoken sentence answering or summarizing for the user —
 it is read aloud by TTS; never mention JSON, components, or the interface>",
 "components": [<flat A2UI component list, root Column with id "root">],
 "dataModel": {}}
Never emit a SourceChips component — the server attaches sources itself.
Use Google Search ONLY when the answer depends on current or recent
information (live prices, rates, news, schedules, results). For timeless
questions — explanations, how-tos, letters, plans, comparisons of stable
things — answer directly with the JSON, without searching.
If the answer would be wrong or misleading without current real-world data
(today's prices, tariffs or plan rates, news, schedules, availability) and
you cannot search, respond with EXACTLY {"needsSearch": true} and nothing
else — the server will re-ask you with search enabled. Never use it for
timeless questions.
The server also holds live Indian utility data. If the question is about one
of these topics — however it is phrased, in any language — respond with
EXACTLY {"needsData": {"source": "<name>"}} and nothing else; the server
fetches the data and re-asks you with it:
- "aqi": city air quality / pollution levels (CPCB, all-India)
- "weather": city weather and forecast
- "panchang": tithi, nakshatra, muhurat, rahu kalam for a date
- "cricket": the live cricket match score
Prefer needsData over needsSearch for these topics.
"""

# Second phase of the needsData flow: compose the surface from adapter data.
# The data is placed in the surface dataModel under /{source} so hero
# components bind to it (catalog rule 6) instead of copying values.
_COMPOSE_FROM_DATA = (
    "The user asked: {query}\n\n"
    'The server fetched live "{source}" data. This exact JSON is already '
    'available in the surface dataModel at "/{source}":\n---\n{data}\n---\n'
    "Compose the answer surface from this data only. Bind component props "
    'with {{"path": "/{source}/..."}} references where the data has the '
    "value. Do not invent facts beyond this data."
)

# When the model grounds with search it answers in plain text and drops the
# JSON contract — this second-phase prompt composes the surface from that
# grounded answer (run in strict JSON mode, no tools).
_COMPOSE_FROM_TEXT = (
    "The user asked: {query}\n\n"
    "A web search already produced this factual answer:\n---\n{answer}\n---\n"
    "Compose the answer surface JSON from this information only. Do not "
    "invent facts beyond it."
)

# `"caption": "…"` is the first key the model emits, so it usually parses out
# of the stream within the first chunks — long before components finish.
_CAPTION_RE = re.compile(r'"caption"\s*:\s*"((?:[^"\\]|\\.)*)"')

# The ungrounded path's escape hatch: the model answers {"needsSearch": true}
# when the answer needs current data it doesn't have, and the server re-runs
# the query with search enabled. The gate stays server-owned — the model can
# only *request* a search, never trigger one directly.
_NEEDS_SEARCH_RE = re.compile(r'"needsSearch"\s*:\s*true')


def _wants_search(text: str) -> bool:
    return bool(_NEEDS_SEARCH_RE.search(text.strip()[:200]))


# The unified data path: adapters the model can request by name (the server
# executes — whitelisted here, never model-supplied code or URLs). Every
# adapter is (query, lang) -> data dict and falls back to fixtures on error;
# templates.py keys the hero data model by the same names.
_DATA_SOURCES = {
    "aqi": aqi.get_aqi,
    "weather": weather.get_weather,
    "panchang": panchang.get_daily_panchang,
    "cricket": cricket.get_live_match,
}


def _data_request(text: str) -> str | None:
    """Extracts the source name from a {"needsData": ...} reply, else None."""
    head = text.strip()
    if '"needsData"' not in head[:200]:
        return None
    start = head.find("{")
    if start < 0:
        return None
    try:
        payload, _ = json.JSONDecoder(strict=False).raw_decode(head[start:])
    except json.JSONDecodeError:
        return None
    request = payload.get("needsData")
    if isinstance(request, dict):
        return str(request.get("source") or "") or None
    if isinstance(request, str):
        return request or None
    return None

# Server-side grounding gate. With the google_search tool present, Flash-Lite
# searches for ~3/4 of queries regardless of prompt instructions (measured on
# the eval set) — tripling latency and burning grounded-query quota. So the
# SERVER decides: ground only queries that smell time-sensitive; everything
# else takes the fast strict-JSON path.
_FRESHNESS_KEYWORDS = [
    "today", "tonight", "tomorrow", "yesterday", "now", "latest", "current",
    "currently", "recent", "this year", "this week", "this month", "news",
    "price", "prices", "rate", "rates", "cost of", "how much is", "schedule",
    "when is", "results", "score", "update", "2025", "2026",
    # commercial offers change monthly and the model answers stale ones
    # confidently — ground them (known miss: "jio vs airtel plans under 300")
    "recharge", "plans under", "plan under", "tariff", "data pack", "offers",
    "रिचार्ज", "प्लान", "ऑफर", "రీఛార్జ్", "ప్లాన్", "ఆఫర్",
    "आज", "अभी", "कल", "ताज़ा", "ताजा", "कीमत", "भाव", "रेट", "इस साल",
    "इस हफ्ते", "खबर", "कब है", "कितना है",
    "నేడు", "ఇప్పుడు", "రేపు", "తాజా", "ధర", "రేటు", "ఈ సంవత్సరం",
    "ఈ వారం", "వార్తలు", "ఎప్పుడు", "ఎంత",
]


def needs_freshness(query: str) -> bool:
    q = query.casefold()
    return any(keyword in q for keyword in _FRESHNESS_KEYWORDS)

_THINKING = {
    "en": "Thinking…",
    "hi": "सोच रहा हूँ…",
    "te": "ఆలోచిస్తున్నాను…",
}

_MOCK_TEXT = {
    "en": "This is a mock generic answer (no LLM provider configured). The real "
          "generic tier sends your question to the model with the Nakul "
          "catalog and renders whatever it composes.",
    "hi": "यह एक मॉक जवाब है (कोई LLM प्रोवाइडर सेट नहीं है)। असली जेनेरिक टियर "
          "आपका सवाल मॉडल को भेजता है और जो UI बनता है उसे दिखाता है।",
    "te": "ఇది మాక్ సమాధానం (LLM ప్రొవైడర్ సెట్ కాలేదు). నిజమైన జెనరిక్ టియర్ "
          "మీ ప్రశ్నను మోడల్‌కి పంపి వచ్చిన UI ని చూపిస్తుంది.",
}
_MOCK_CAPTION = {
    "en": "Here's what I found.",
    "hi": "यह रहा आपका जवाब।",
    "te": "ఇదిగో మీ సమాధానం.",
}
_MOCK_CHIPS = {
    "en": [{"label": "Tell me more", "query": "tell me more"},
           {"label": "Example?", "query": "give me an example"}],
    "hi": [{"label": "और बताओ", "query": "और बताओ"},
           {"label": "उदाहरण?", "query": "एक उदाहरण दो"}],
    "te": [{"label": "ఇంకా చెప్పు", "query": "ఇంకా చెప్పు"},
           {"label": "ఉదాహరణ?", "query": "ఒక ఉదాహరణ ఇవ్వు"}],
}
_DEGRADE_TEXT = {
    "en": "I couldn't build a visual answer for that just now — try again.",
    "hi": "अभी इसका विज़ुअल जवाब नहीं बन पाया — फिर से कोशिश करें।",
    "te": "ప్రస్తుతం దీనికి విజువల్ సమాధానం రాలేదు — మళ్లీ ప్రయత్నించండి.",
}


def get_provider() -> Provider:
    return _PROVIDERS[os.environ.get("LLM_PROVIDER", "gemini")]


def placeholder_components(lang: str) -> list[dict[str, Any]]:
    return [
        {"id": "root", "component": "Column", "children": ["thinking"]},
        {"id": "thinking", "component": "Text", "variant": "caption", "text": _THINKING[lang]},
    ]


# Grounded preview: while the two-phase grounded flow runs (search answer →
# compose pass, ~15s total), the phase-1 plain-text answer streams into this
# Markdown surface via data-model updates, so the user reads the answer in
# seconds and the composed surface is an upgrade, not the first paint.
_PREVIEW_PATH = "groundedText"
_PREVIEW_PUSH_CHARS = 120  # min new chars between updateDataModel pushes


def _preview_components() -> list[dict[str, Any]]:
    return [
        {"id": "root", "component": "Column", "children": ["grounded_answer"]},
        {"id": "grounded_answer", "component": "Markdown", "text": {"path": f"/{_PREVIEW_PATH}"}},
    ]


_SENTENCE_END_RE = re.compile(r"[.!?।]['\")”]?(?:\s|$)")


def _first_sentence(text: str, limit: int = 160) -> str:
    """Caption for a plain-text grounded answer: its first sentence, cleaned
    of markdown syntax (the caption is spoken, not rendered)."""
    plain = re.sub(r"[#*_`>|]+", " ", text)
    plain = " ".join(plain.split())
    match = _SENTENCE_END_RE.search(plain)
    if match and match.end() <= limit:
        return plain[: match.end()].strip()
    if len(plain) <= limit:
        return plain
    return plain[:limit].rsplit(" ", 1)[0] + "…"


def _fallback_surface(text: str, lang: str) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    components = [
        {"id": "root", "component": "Column", "children": ["answer", "chips"]},
        {"id": "answer", "component": "Markdown", "text": text},
        {"id": "chips", "component": "FollowUpChips", "suggestions": _MOCK_CHIPS[lang]},
    ]
    return _MOCK_CAPTION[lang], components, {}


def _normalize_component_shapes(components: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Deterministic repairs for known LLM shape mistakes (content untouched).

    - ComparisonTable cells as [{key, value}] or {col: value} → ordered strings
    - hallucinated top-level props pruned (validator would reject; renderer
      would ignore)
    """
    for comp in components:
        allowed = known_props(str(comp.get("component")))
        if allowed is not None:
            for prop in [k for k in comp if k not in allowed]:
                del comp[prop]
    for comp in components:
        if comp.get("component") == "ComparisonTable":
            keys = [c.get("key") for c in comp.get("columns") or [] if isinstance(c, dict)]
            for row in comp.get("rows") or []:
                cells = row.get("cells")
                if isinstance(cells, list) and cells and all(isinstance(c, dict) for c in cells):
                    by_key = {c.get("key"): str(c.get("value", "")) for c in cells}
                    if keys and all(k in by_key for k in keys):
                        row["cells"] = [by_key[k] for k in keys]
                    else:
                        row["cells"] = [str(c.get("value", "")) for c in cells]
                elif isinstance(cells, dict):
                    if keys and all(k in cells for k in keys):
                        row["cells"] = [str(cells[k]) for k in keys]
                    else:
                        row["cells"] = [str(v) for v in cells.values()]
    return components


_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.MULTILINE)


def _enrich_surface(
    components: list[dict[str, Any]], lang: str, caption: str
) -> list[dict[str, Any]]:
    """Deterministic product guarantees around otherwise model-owned layouts.

    A recipe always gets one visual, derived from its own generated title and
    summary, and every finished answer gets follow-ups. The model still owns
    the rest of the composition and content.
    """
    root = next((c for c in components if c.get("id") == "root"), None)
    if root is None:
        return components
    children = list(root.get("children") or [])
    types = {str(c.get("component")) for c in components}

    if "RecipeCard" in types and "GeneratedVisual" not in types:
        recipe = next(c for c in components if c.get("component") == "RecipeCard")
        title = str(recipe.get("title") or "the finished dish")
        summary = str(recipe.get("summary") or "freshly prepared and ready to serve")
        visual_id = "recipe_visual"
        existing_ids = {str(c.get("id")) for c in components}
        suffix = 2
        while visual_id in existing_ids:
            visual_id = f"recipe_visual_{suffix}"
            suffix += 1
        visual = {
            "id": visual_id,
            "component": "GeneratedVisual",
            "prompt": (
                f"A finished serving of {title}; {summary}. Three-quarter close view "
                "with the key ingredients visible nearby, appetizing and natural."
            )[:500],
            "alt": (title if len(title.strip()) >= 3 else "Finished dish")[:180],
            "aspectRatio": "landscape",
        }
        recipe_id = str(recipe.get("id"))
        insert_at = children.index(recipe_id) if recipe_id in children else 0
        children.insert(insert_at, visual_id)
        components.append(visual)

    if "FollowUpChips" not in types:
        chips_id = "follow_up"
        existing_ids = {str(c.get("id")) for c in components}
        suffix = 2
        while chips_id in existing_ids:
            chips_id = f"follow_up_{suffix}"
            suffix += 1
        suggestions = _MOCK_CHIPS[lang]
        if lang == "en" and caption:
            subject = caption[:180]
            suggestions = [
                {"label": "Go deeper", "query": f"Tell me more about this: {subject}"},
                {
                    "label": "Make it practical",
                    "query": f"Give me the most practical next step for this: {subject}",
                },
            ]
        components.append(
            {
                "id": chips_id,
                "component": "FollowUpChips",
                "suggestions": suggestions,
            }
        )
        children.append(chips_id)

    root["children"] = children
    return components


def _parse_and_validate(
    text: str, lang: str = "en"
) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    # Without JSON mode (grounding forbids it) models may wrap output in
    # markdown fences or append stray tokens — strip fences, take the first
    # complete object, tolerate literal newlines in strings.
    cleaned = _FENCE_RE.sub("", text.strip()).strip()
    start = cleaned.find("{")
    if start < 0:
        raise json.JSONDecodeError("no JSON object found", cleaned, 0)
    payload, _ = json.JSONDecoder(strict=False).raw_decode(cleaned[start:])
    caption = str(payload["caption"])
    components = _normalize_component_shapes(flatten_components(payload["components"]))
    components = _enrich_surface(components, lang, caption)
    data_model = payload.get("dataModel") or {}
    validate_surface(components)
    return caption, components, data_model


def _attach_sources(
    components: list[dict[str, Any]], sources: list[Source]
) -> list[dict[str, Any]]:
    """Appends a server-built SourceChips before FollowUpChips (R1 ordering)."""
    if not sources:
        return components
    # drop any model-fabricated SourceChips first (prompt forbids it, belt+braces)
    components = [c for c in components if c.get("component") != "SourceChips"]
    root = next((c for c in components if c.get("id") == "root"), None)
    if root is None:
        return components
    chip = {
        "id": "web_sources",
        "component": "SourceChips",
        "sources": [
            {"title": s.title[:80], "domain": s.domain[:60], "url": s.url}
            for s in sources[:5]
        ],
    }
    children = list(root.get("children") or [])
    chips_index = next(
        (i for i, cid in enumerate(children)
         if any(c.get("id") == cid and c.get("component") == "FollowUpChips" for c in components)),
        len(children),
    )
    children.insert(chips_index, "web_sources")
    root["children"] = children
    components.append(chip)
    validate_surface(components)
    return components


def _system_prompt(lang: str) -> str:
    return PROMPT_PATH.read_text() + f"\nOutput language: {_LANG_NAME[lang]}.\n" + _OUTPUT_CONTRACT


def _turns(query: str, history: list[dict[str, str]]) -> list[Turn]:
    turns = [Turn(role=h["role"], text=h["text"][:500]) for h in history[-12:]]
    turns.append(Turn(role="user", text=query))
    return turns


class _GenState:
    """Mutable result carried through the streaming passes (async generators
    can't return values)."""

    def __init__(self) -> None:
        self.caption = ""
        self.caption_sent = False
        self.components: list[dict[str, Any]] | None = None
        self.data_model: dict[str, Any] = {}
        self.sources: list[Source] = []
        self.grounded_text = ""  # phase-1 plain-text answer, if search ran
        self.escalate = False  # ungrounded model requested a search
        self.data_request: str | None = None  # model requested an adapter
        self.hero_data: dict[str, Any] = {}  # fetched adapter data, keyed by source
        self.repair_turns: list[Turn] | None = None  # prompt to replay on repair


def _set_parsed(state: _GenState, text: str, lang: str) -> None:
    state.caption, state.components, state.data_model = _parse_and_validate(text, lang)


async def _fast_json_pass(
    provider: Provider, system: str, turns: list[Turn],
    state: _GenState, surface_id: str, lang: str, query: str,
) -> AsyncIterator[str]:
    """Ungrounded strict-JSON path (the common case, p50 ~5s)."""
    buffer = ""
    async for event in provider.stream(system, turns, grounded=False):
        if isinstance(event, Chunk):
            buffer += event.text
            if not state.caption_sent:
                match = _CAPTION_RE.search(buffer)
                if match:
                    state.caption = json.loads(f'"{match.group(1)}"')
                    state.caption_sent = True
                    yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
        elif isinstance(event, Final):
            buffer = event.text
            state.sources = event.sources
    source = _data_request(buffer)
    if source is not None:
        if source in _DATA_SOURCES:
            state.data_request = source
        else:
            # Unknown source — grounded search can answer anything current.
            log.info("model requested unknown data source %r; escalating to search", source)
            state.escalate = True
        return
    if _wants_search(buffer):
        state.escalate = True
        return
    state.repair_turns = turns
    try:
        _set_parsed(state, buffer, lang)
    except json.JSONDecodeError:
        if not buffer.strip():
            raise
        # JSON mode should prevent this, but if the model answered in prose
        # anyway, compose a surface from it rather than failing.
        log.info("ungrounded plain-text answer; running compose pass")
        async for msg in _compose_pass(provider, system, query, buffer, state, surface_id, lang):
            yield msg


async def _grounded_pass(
    provider: Provider, system: str, turns: list[Turn],
    state: _GenState, surface_id: str, lang: str, query: str,
) -> AsyncIterator[str]:
    """Search-grounded path with a live preview.

    When the model searches it drops the JSON contract and answers in plain
    text; that text streams into a Markdown preview surface immediately
    (caption from its first sentence, sources attached), then the compose
    pass upgrades it to the full visual surface.
    """
    buffer = ""
    preview_started = False
    pushed_len = 0
    async for event in provider.stream(system, turns, grounded=True):
        if isinstance(event, Chunk):
            buffer += event.text
            head = buffer.lstrip()
            if not head:
                continue
            if head.startswith(("{", "```")):
                # JSON contract held — the model chose not to search.
                if not state.caption_sent:
                    match = _CAPTION_RE.search(buffer)
                    if match:
                        state.caption = json.loads(f'"{match.group(1)}"')
                        state.caption_sent = True
                        yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
                continue
            # Plain text — the model searched. Stream it into the preview.
            if not state.caption_sent:
                caption = _first_sentence(head)
                if _SENTENCE_END_RE.search(caption) or len(caption) >= 80:
                    state.caption = caption
                    state.caption_sent = True
                    yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
            if not preview_started:
                preview_started = True
                pushed_len = len(head)
                yield a2ui.ndjson(
                    a2ui.update_data_model(surface_id, {_PREVIEW_PATH: head}),
                    a2ui.update_components(surface_id, _preview_components()),
                )
            elif len(head) - pushed_len >= _PREVIEW_PUSH_CHARS:
                pushed_len = len(head)
                yield a2ui.ndjson(a2ui.update_data_model(surface_id, {_PREVIEW_PATH: head}))
        elif isinstance(event, Final):
            buffer = event.text
            state.sources = event.sources

    text = buffer.strip()
    if not preview_started and text.startswith(("{", "```")):
        if _wants_search(text):
            raise ValueError("model requested search while search was enabled")
        state.repair_turns = turns
        _set_parsed(state, text, lang)
        return

    if not text:
        raise json.JSONDecodeError("empty grounded answer", "", 0)
    state.grounded_text = text
    if not state.caption_sent:
        state.caption = _first_sentence(text)
        state.caption_sent = True
        yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
    # Complete preview: full text plus sources, so the user has the whole
    # grounded answer (attributed) while the compose pass runs.
    final_preview = [a2ui.update_data_model(surface_id, {_PREVIEW_PATH: text})]
    if not preview_started:
        final_preview.append(a2ui.update_components(surface_id, _preview_components()))
    elif state.sources:
        try:
            final_preview.append(a2ui.update_components(
                surface_id, _attach_sources(_preview_components(), state.sources)))
        except SurfaceValidationError:
            pass
    yield a2ui.ndjson(*final_preview)

    async for msg in _compose_pass(provider, system, query, text, state, surface_id, lang):
        yield msg


async def _data_pass(
    provider: Provider, system: str, source: str,
    state: _GenState, surface_id: str, lang: str, query: str,
) -> AsyncIterator[str]:
    """Unified data path: fetch the requested adapter's data, then compose a
    surface from it. The data lands in the surface dataModel under /{source},
    so the model binds hero components exactly like server templates do."""
    log.info("model requested data source %r; fetching adapter", source)
    data = await _DATA_SOURCES[source](query, lang)
    state.hero_data = {source: data}
    prompt = _COMPOSE_FROM_DATA.format(
        query=query, source=source,
        data=json.dumps(data, ensure_ascii=False)[:4000],
    )
    compose_turns = [Turn("user", prompt)]
    state.repair_turns = compose_turns
    buffer = ""
    async for event in provider.stream(system, compose_turns, grounded=False):
        if isinstance(event, Chunk):
            buffer += event.text
            if not state.caption_sent:
                match = _CAPTION_RE.search(buffer)
                if match:
                    state.caption = json.loads(f'"{match.group(1)}"')
                    state.caption_sent = True
                    yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
        elif isinstance(event, Final):
            buffer = event.text
    _set_parsed(state, buffer, lang)


async def _compose_pass(
    provider: Provider, system: str, query: str, answer: str,
    state: _GenState, surface_id: str, lang: str,
) -> AsyncIterator[str]:
    """Second phase: compose the visual surface from a plain-text answer,
    in strict JSON mode (search grounding forbids JSON mode, hence two-phase)."""
    log.info("running compose pass over plain-text answer")
    compose_turns = [Turn("user", _COMPOSE_FROM_TEXT.format(query=query, answer=answer[:4000]))]
    state.repair_turns = compose_turns
    buffer = ""
    async for event in provider.stream(system, compose_turns, grounded=False):
        if isinstance(event, Chunk):
            buffer += event.text
            if not state.caption_sent:
                match = _CAPTION_RE.search(buffer)
                if match:
                    state.caption = json.loads(f'"{match.group(1)}"')
                    state.caption_sent = True
                    yield a2ui.ndjson(a2ui.caption_message(surface_id, state.caption, lang))
        elif isinstance(event, Final):
            buffer = event.text
    _set_parsed(state, buffer, lang)


async def generate_generic_stream(
    query: str,
    lang: str,
    surface_id: str,
    history: list[dict[str, str]] | None = None,
) -> AsyncIterator[str]:
    """Streams NDJSON for a generic answer, progressively:

    1. placeholder surface immediately (perceived latency ≈ 0)
    2. caption line as soon as it parses out of the model stream
    3. for grounded queries: the phase-1 search answer as a live Markdown
       preview (with sources) while the compose pass runs
    4. validated final surface (+ grounding SourceChips), with one
       validation-feedback repair retry

    The ungrounded path may escalate to the grounded one when the model
    answers {"needsSearch": true} (freshness-gate misses); the reverse never
    happens. Fail-closed is preserved: only the placeholder, the Markdown
    preview (our components, model text), and fully validated surfaces reach
    the wire.
    """
    yield a2ui.ndjson(
        a2ui.create_surface(surface_id, catalog_id()),
        a2ui.update_data_model(surface_id, {}),
        a2ui.update_components(surface_id, placeholder_components(lang)),
    )

    provider = get_provider()
    if not provider.available():
        caption, components, data_model = _fallback_surface(_MOCK_TEXT[lang], lang)
        yield a2ui.ndjson(
            a2ui.caption_message(surface_id, caption, lang),
            a2ui.update_data_model(surface_id, data_model),
            a2ui.update_components(surface_id, components),
        )
        return

    system = _system_prompt(lang)
    turns = _turns(query, history or [])
    state = _GenState()

    grounded = needs_freshness(query)
    try:
        if not grounded:
            async for msg in _fast_json_pass(provider, system, turns, state, surface_id, lang, query):
                yield msg
            if state.data_request:
                async for msg in _data_pass(
                    provider, system, state.data_request, state, surface_id, lang, query,
                ):
                    yield msg
            elif state.escalate:
                log.info("model requested search; escalating to grounded flow")
                grounded = True
        if grounded and state.components is None:
            async for msg in _grounded_pass(provider, system, turns, state, surface_id, lang, query):
                yield msg
    except SurfaceValidationError as first:
        # Repair loop: one retry with the validation errors as feedback,
        # replayed against whichever prompt produced the invalid output.
        log.info("generic tier invalid, retrying with feedback: %s", first.errors[:3])
        base = state.repair_turns or turns
        feedback = (
            f"{base[-1].text}\n\n[system] Your previous response failed catalog "
            f"validation with these errors:\n- " + "\n- ".join(first.errors[:10]) +
            "\nRespond again with a corrected JSON object that satisfies the catalog."
        )
        try:
            final = await provider.complete(system, [*base[:-1], Turn("user", feedback)])
            _set_parsed(state, final.text, lang)
        except Exception:
            log.warning("generic tier invalid after retry, degrading")
            _degrade(state, lang)
    except Exception:
        log.exception("generic tier failed, degrading to text surface")
        _degrade(state, lang)

    try:
        state.components = _attach_sources(state.components, state.sources)
    except SurfaceValidationError:
        log.warning("source attachment failed validation; shipping without sources")

    if state.hero_data:
        # Adapter data underpins the surface's {path} bindings — merge it in
        # whichever way the surface was produced (compose, repair, degrade).
        state.data_model = {**state.hero_data, **state.data_model}

    messages: list[dict[str, Any]] = []
    if not state.caption_sent:
        messages.append(a2ui.caption_message(surface_id, state.caption, lang))
    messages.append(a2ui.update_data_model(surface_id, state.data_model))
    messages.append(a2ui.update_components(surface_id, state.components))
    yield a2ui.ndjson(*messages)


def _degrade(state: _GenState, lang: str) -> None:
    """Last resort — but if the grounded phase already produced a good
    plain-text answer, keep it (with sources) instead of an apology."""
    if state.grounded_text:
        log.info("compose failed; finalizing the grounded preview as the answer")
        state.caption, state.components, state.data_model = _fallback_surface(
            state.grounded_text, lang)
    else:
        state.caption, state.components, state.data_model = _fallback_surface(
            _DEGRADE_TEXT[lang], lang)
        state.sources = []
