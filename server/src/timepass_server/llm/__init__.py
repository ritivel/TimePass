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
from ..validator import SurfaceValidationError, catalog_id, known_props, validate_surface
from .base import Chunk, Final, Provider, Source, Turn
from .gemini import GeminiProvider

log = logging.getLogger(__name__)

PROMPT_PATH = Path(__file__).resolve().parents[4] / "catalog" / "dist" / "system_prompt.md"

_PROVIDERS: dict[str, Provider] = {"gemini": GeminiProvider()}

_LANG_NAME = {"en": "English", "hi": "Hindi", "te": "Telugu"}

_OUTPUT_CONTRACT = """
Respond with ONLY a JSON object — no prose, no markdown code fences — of the form:
{"caption": "<one spoken sentence in the output language>",
 "components": [<flat A2UI component list, root Column with id "root">],
 "dataModel": {}}
Never emit a SourceChips component — the server attaches sources itself.
Use Google Search ONLY when the answer depends on current or recent
information (live prices, rates, news, schedules, results). For timeless
questions — explanations, how-tos, letters, plans, comparisons of stable
things — answer directly with the JSON, without searching.
"""

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
          "generic tier sends your question to the model with the TimePass "
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


def _parse_and_validate(text: str) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
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


async def generate_generic_stream(
    query: str,
    lang: str,
    surface_id: str,
    history: list[dict[str, str]] | None = None,
) -> AsyncIterator[str]:
    """Streams NDJSON for a generic answer, progressively:

    1. placeholder surface immediately (perceived latency ≈ 0)
    2. caption line as soon as it parses out of the model stream
    3. validated final surface (+ grounding SourceChips), with one
       validation-feedback repair retry

    Fail-closed is preserved: only the placeholder (static, ours) and a fully
    validated surface ever reach the wire.
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

    caption_sent = False
    caption = ""
    components: list[dict[str, Any]] | None = None
    data_model: dict[str, Any] = {}
    sources: list[Source] = []

    grounded = needs_freshness(query)
    try:
        buffer = ""
        async for event in provider.stream(system, turns, grounded=grounded):
            if isinstance(event, Chunk):
                buffer += event.text
                if not caption_sent:
                    match = _CAPTION_RE.search(buffer)
                    if match:
                        caption = json.loads(f'"{match.group(1)}"')
                        caption_sent = True
                        yield a2ui.ndjson(a2ui.caption_message(surface_id, caption, lang))
            elif isinstance(event, Final):
                sources = event.sources
                buffer = event.text
        try:
            caption, components, data_model = _parse_and_validate(buffer)
        except json.JSONDecodeError:
            if not buffer.strip():
                raise
            # Grounded plain-text answer (search overrides the JSON contract):
            # second pass composes the surface from it, in strict JSON mode.
            log.info("grounded plain-text answer; running compose pass")
            compose_turns = [
                Turn("user", _COMPOSE_FROM_TEXT.format(query=query, answer=buffer[:4000]))
            ]
            buffer = ""
            async for event in provider.stream(system, compose_turns, grounded=False):
                if isinstance(event, Chunk):
                    buffer += event.text
                    if not caption_sent:
                        match = _CAPTION_RE.search(buffer)
                        if match:
                            caption = json.loads(f'"{match.group(1)}"')
                            caption_sent = True
                            yield a2ui.ndjson(
                                a2ui.caption_message(surface_id, caption, lang)
                            )
                elif isinstance(event, Final):
                    buffer = event.text
            caption, components, data_model = _parse_and_validate(buffer)
    except SurfaceValidationError as first:
        # Repair loop: one retry with the validation errors as feedback.
        log.info("generic tier invalid, retrying with feedback: %s", first.errors[:3])
        feedback = (
            f"{query}\n\n[system] Your previous response failed catalog "
            f"validation with these errors:\n- " + "\n- ".join(first.errors[:10]) +
            "\nRespond again with a corrected JSON object that satisfies the catalog."
        )
        try:
            final = await provider.complete(system, [*turns[:-1], Turn("user", feedback)])
            caption, components, data_model = _parse_and_validate(final.text)
        except Exception:
            log.warning("generic tier invalid after retry, degrading")
            caption, components, data_model = _fallback_surface(_DEGRADE_TEXT[lang], lang)
            sources = []
    except Exception:
        log.exception("generic tier failed, degrading to text surface")
        caption, components, data_model = _fallback_surface(_DEGRADE_TEXT[lang], lang)
        sources = []

    try:
        components = _attach_sources(components, sources)
    except SurfaceValidationError:
        log.warning("source attachment failed validation; shipping without sources")

    messages: list[dict[str, Any]] = []
    if not caption_sent:
        messages.append(a2ui.caption_message(surface_id, caption, lang))
    messages.append(a2ui.update_data_model(surface_id, data_model))
    messages.append(a2ui.update_components(surface_id, components))
    yield a2ui.ndjson(*messages)
