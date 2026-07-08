"""A2UI v0.9.1 message builders.

The wire format is NDJSON: one JSON object per line, each an A2UI
server-to-client message ({"version": "v0.9.1", "<messageType>": {...}}).
Components use the v0.9 flat form: {"id", "component", ...props}, with
children referenced by id (adjacency list).
"""

from __future__ import annotations

import json
from typing import Any

# v0.9.1 is a patch release of the v0.9 protocol family; the wire `version`
# field stays "v0.9" — genui 0.9.2's parser rejects anything else.
PROTOCOL_VERSION = "v0.9"


def create_surface(surface_id: str, catalog_id: str) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "createSurface": {
            "surfaceId": surface_id,
            "catalogId": catalog_id,
            "sendDataModel": True,
        },
    }


def update_data_model(surface_id: str, value: dict[str, Any], path: str | None = None) -> dict[str, Any]:
    msg: dict[str, Any] = {"surfaceId": surface_id, "value": value}
    if path is not None:
        msg["path"] = path
    return {"version": PROTOCOL_VERSION, "updateDataModel": msg}


def update_components(surface_id: str, components: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "updateComponents": {"surfaceId": surface_id, "components": components},
    }


def caption_message(surface_id: str, caption: str, lang: str) -> dict[str, Any]:
    """TimePass extension line (not part of A2UI): the one-line TTS caption.

    The Flutter client reads this for the caption bar / TTS and must not feed
    it to the A2UI transport adapter.
    """
    return {"timepass": {"surfaceId": surface_id, "caption": caption, "lang": lang}}


def ndjson(*messages: dict[str, Any]) -> str:
    return "".join(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n" for m in messages)


def flatten_components(components: list[Any]) -> list[dict[str, Any]]:
    """Normalizes LLM output to the flat adjacency-list form.

    Models frequently nest component objects inside `children`/`child`
    despite instructions. That's deterministic to repair: hoist nested
    components to the top-level list and replace them with their ids
    (synthesizing ids where missing). Validation still runs afterwards —
    this fixes shape, never content.
    """
    out: list[dict[str, Any]] = []
    counter = 0

    def ensure_id(comp: dict[str, Any]) -> str:
        nonlocal counter
        if not comp.get("id"):
            counter += 1
            comp["id"] = f"c{counter}"
        return comp["id"]

    def walk(comp: dict[str, Any]) -> str:
        comp = dict(comp)
        children = comp.get("children")
        if isinstance(children, list):
            comp["children"] = [
                walk(item) if isinstance(item, dict) and "component" in item else item
                for item in children
            ]
        child = comp.get("child")
        if isinstance(child, dict) and "component" in child:
            comp["child"] = walk(child)
        out.append(comp)
        return ensure_id(comp)

    for comp in components:
        if isinstance(comp, dict):
            walk(comp)
    return out
