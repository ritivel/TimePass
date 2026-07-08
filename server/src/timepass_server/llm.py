"""Generic-tier answer generation (Gemini Flash-Lite) with an offline mock.

Real mode requires GEMINI_API_KEY. The model must return strict JSON:
{"caption": str, "components": [flat A2UI component list], "dataModel": {}}.
Anything that fails parsing or catalog validation degrades to a plain
Markdown surface (fail closed on structure, graceful on content).
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from .a2ui import flatten_components
from .validator import SurfaceValidationError, validate_surface

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


def _fallback_surface(text: str, lang: str) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    components = [
        {"id": "root", "component": "Column", "children": ["answer", "chips"]},
        {"id": "answer", "component": "Markdown", "text": text},
        {"id": "chips", "component": "FollowUpChips", "suggestions": _MOCK_CHIPS[lang]},
    ]
    return _MOCK_CAPTION[lang], components, {}


async def generate_generic(query: str, lang: str) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return _fallback_surface(_MOCK_TEXT[lang], lang)

    from google import genai  # imported lazily so mock mode needs no network deps

    client = genai.Client(api_key=api_key)
    system = (
        PROMPT_PATH.read_text()
        + f"\nOutput language: {_LANG_NAME[lang]}.\n"
        + _OUTPUT_CONTRACT
    )

    async def attempt(contents) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
        response = await client.aio.models.generate_content(
            model=MODEL,
            contents=contents,
            config={
                "system_instruction": system,
                "response_mime_type": "application/json",
                "temperature": 0.4,
            },
        )
        payload = json.loads(response.text)
        caption = str(payload["caption"])
        components = flatten_components(payload["components"])
        data_model = payload.get("dataModel") or {}
        validate_surface(components)
        return caption, components, data_model

    try:
        try:
            return await attempt(query)
        except SurfaceValidationError as first:
            # Standard genUI repair loop: one retry with the validation
            # errors as feedback. Failures only, so the marginal cost is
            # one extra call on a small fraction of queries.
            log.info("generic tier invalid, retrying with feedback: %s", first.errors[:3])
            feedback = (
                f"{query}\n\n[system] Your previous response failed catalog "
                f"validation with these errors:\n- " + "\n- ".join(first.errors[:10]) +
                "\nRespond again with a corrected JSON object that satisfies the catalog."
            )
            return await attempt(feedback)
    except SurfaceValidationError as e:
        log.warning("generic tier invalid after retry, degrading: %s", e.errors[:5])
    except Exception:
        log.exception("generic tier failed, degrading to text surface")
    # degrade: answer as plain text via a second, schema-free call is a later
    # optimization; M0 keeps the failure honest and visible.
    fallback = {
        "en": "I couldn't build a visual answer for that just now — try again.",
        "hi": "अभी इसका विज़ुअल जवाब नहीं बन पाया — फिर से कोशिश करें।",
        "te": "ప్రస్తుతం దీనికి విజువల్ సమాధానం రాలేదు — మళ్లీ ప్రయత్నించండి.",
    }
    return _fallback_surface(fallback[lang], lang)
