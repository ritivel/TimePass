"""Generic-tier answer generation (Gemini Flash-Lite) with an offline mock.

Real mode requires GEMINI_API_KEY. The model must return strict JSON:
{"caption": str, "components": [flat A2UI component list], "dataModel": {}}.
Anything that fails parsing or catalog validation degrades to a plain
Markdown surface (fail closed on structure, graceful on content).
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

from . import a2ui
from .a2ui import flatten_components
from .validator import SurfaceValidationError, known_props, validate_surface

log = logging.getLogger(__name__)

PROMPT_PATH = Path(__file__).resolve().parents[3] / "catalog" / "dist" / "system_prompt.md"
MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite")

_LANG_NAME = {"en": "English", "hi": "Hindi", "te": "Telugu"}

_OUTPUT_CONTRACT = """
Respond with ONLY a JSON object, no prose, of the form:
{"caption": "<one spoken sentence in the output language>",
 "components": [<flat A2UI component list, root Column with id "root">],
 "dataModel": {}}
"""

_MOCK_TEXT = {
    "en": "This is a mock generic answer (no GEMINI_API_KEY set). The real "
          "generic tier sends your question to Gemini with the TimePass "
          "catalog and renders whatever it composes.",
    "hi": "यह एक मॉक जवाब है (GEMINI_API_KEY सेट नहीं है)। असली जेनेरिक टियर "
          "आपका सवाल Gemini को भेजता है और जो UI बनता है उसे दिखाता है।",
    "te": "ఇది మాక్ సమాధానం (GEMINI_API_KEY సెట్ కాలేదు). నిజమైన జెనరిక్ టియర్ "
          "మీ ప్రశ్నను Gemini కి పంపి వచ్చిన UI ని చూపిస్తుంది.",
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


_THINKING = {
    "en": "Thinking…",
    "hi": "सोच रहा हूँ…",
    "te": "ఆలోచిస్తున్నాను…",
}

# `"caption": "…"` is the first key the model emits, so it usually parses out
# of the stream within the first chunks — long before components finish.
_CAPTION_RE = re.compile(r'"caption"\s*:\s*"((?:[^"\\]|\\.)*)"')


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

    ComparisonTable: models sometimes emit cells as [{key, value}] objects
    instead of ordered strings — the mapping back is unambiguous. Unknown
    top-level props (hallucinated fields) are pruned; the validator would
    reject them anyway and the renderer would ignore them.
    """
    for comp in components:
        allowed = known_props(str(comp.get("component")))
        if allowed is not None:
            for prop in [k for k in comp if k not in allowed]:
                del comp[prop]
        if comp.get("component") == "ComparisonTable":
            keys = [c.get("key") for c in comp.get("columns") or [] if isinstance(c, dict)]
            for row in comp.get("rows") or []:
                cells = row.get("cells")
                # shape mistake A: [{key: ..., value: ...}] instead of [str]
                if isinstance(cells, list) and cells and all(isinstance(c, dict) for c in cells):
                    by_key = {c.get("key"): str(c.get("value", "")) for c in cells}
                    if keys and all(k in by_key for k in keys):
                        row["cells"] = [by_key[k] for k in keys]
                    else:
                        row["cells"] = [str(c.get("value", "")) for c in cells]
                # shape mistake B: {"jio": "28 days", ...} map keyed by column
                elif isinstance(cells, dict):
                    if keys and all(k in cells for k in keys):
                        row["cells"] = [str(cells[k]) for k in keys]
                    else:
                        row["cells"] = [str(v) for v in cells.values()]
    return components


def _parse_and_validate(text: str) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    # raw_decode: models occasionally append stray tokens after the JSON
    # object even in JSON mode — take the first complete object.
    # strict=False: letters/prose answers often carry literal newlines
    # inside string values.
    payload, _ = json.JSONDecoder(strict=False).raw_decode(text.strip())
    caption = str(payload["caption"])
    components = _normalize_component_shapes(flatten_components(payload["components"]))
    data_model = payload.get("dataModel") or {}
    validate_surface(components)
    return caption, components, data_model


_DEGRADE_TEXT = {
    "en": "I couldn't build a visual answer for that just now — try again.",
    "hi": "अभी इसका विज़ुअल जवाब नहीं बन पाया — फिर से कोशिश करें।",
    "te": "ప్రస్తుతం దీనికి విజువల్ సమాధానం రాలేదు — మళ్లీ ప్రయత్నించండి.",
}


async def generate_generic_stream(
    query: str, lang: str, surface_id: str
) -> AsyncIterator[str]:
    """Streams NDJSON for a generic answer, progressively:

    1. placeholder surface immediately (perceived latency ≈ 0)
    2. caption line as soon as it parses out of the Gemini stream
    3. validated final surface (with one repair retry on validation failure)

    Fail-closed is preserved: only the placeholder (static, ours) and a fully
    validated surface ever reach the wire.
    """
    yield a2ui.ndjson(
        a2ui.create_surface(surface_id, _catalog_id()),
        a2ui.update_data_model(surface_id, {}),
        a2ui.update_components(surface_id, placeholder_components(lang)),
    )

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        caption, components, data_model = _fallback_surface(_MOCK_TEXT[lang], lang)
        yield a2ui.ndjson(
            a2ui.caption_message(surface_id, caption, lang),
            a2ui.update_data_model(surface_id, data_model),
            a2ui.update_components(surface_id, components),
        )
        return

    from google import genai  # imported lazily so mock mode needs no network deps

    client = genai.Client(api_key=api_key)
    system = (
        PROMPT_PATH.read_text()
        + f"\nOutput language: {_LANG_NAME[lang]}.\n"
        + _OUTPUT_CONTRACT
    )
    # NOTE: measured on flash-lite: explicitly setting thinking_config
    # (even budget 0) raises TTFT ~4s. Leave defaults alone.
    config = {
        "system_instruction": system,
        "response_mime_type": "application/json",
        "temperature": 0.4,
    }

    caption_sent = False
    caption = ""
    components: list[dict[str, Any]] | None = None
    data_model: dict[str, Any] = {}

    from google.genai import errors as genai_errors

    try:
        for attempt in range(2):
            try:
                buffer = ""
                stream = await client.aio.models.generate_content_stream(
                    model=MODEL, contents=query, config=config
                )
                async for chunk in stream:
                    buffer += chunk.text or ""
                    if not caption_sent:
                        match = _CAPTION_RE.search(buffer)
                        if match:
                            caption = json.loads(f'"{match.group(1)}"')
                            caption_sent = True
                            yield a2ui.ndjson(
                                a2ui.caption_message(surface_id, caption, lang)
                            )
                caption, components, data_model = _parse_and_validate(buffer)
                break
            except genai_errors.ServerError:
                # 503 "high demand" spikes are common on flash-lite free
                # tier and usually clear in seconds.
                if attempt == 0:
                    log.info("Gemini 5xx, retrying once after backoff")
                    await asyncio.sleep(1.5)
                    continue
                raise
    except SurfaceValidationError as first:
        # Repair loop: one retry with the validation errors as feedback.
        log.info("generic tier invalid, retrying with feedback: %s", first.errors[:3])
        feedback = (
            f"{query}\n\n[system] Your previous response failed catalog "
            f"validation with these errors:\n- " + "\n- ".join(first.errors[:10]) +
            "\nRespond again with a corrected JSON object that satisfies the catalog."
        )
        try:
            response = await client.aio.models.generate_content(
                model=MODEL, contents=feedback, config=config
            )
            caption, components, data_model = _parse_and_validate(response.text)
        except Exception:
            log.warning("generic tier invalid after retry, degrading")
            caption, components, data_model = _fallback_surface(_DEGRADE_TEXT[lang], lang)
    except Exception:
        log.exception("generic tier failed, degrading to text surface")
        caption, components, data_model = _fallback_surface(_DEGRADE_TEXT[lang], lang)

    messages: list[dict[str, Any]] = []
    if not caption_sent or components is None:
        messages.append(a2ui.caption_message(surface_id, caption, lang))
    messages.append(a2ui.update_data_model(surface_id, data_model))
    messages.append(a2ui.update_components(surface_id, components))
    yield a2ui.ndjson(*messages)


def _catalog_id() -> str:
    from .validator import catalog_id

    return catalog_id()
