"""A2UI v0.9.1 message builders.

The wire format is NDJSON: one JSON object per line, each an A2UI
server-to-client message ({"version": "v0.9.1", "<messageType>": {...}}).
Components use the v0.9 flat form: {"id", "component", ...props}, with
children referenced by id (adjacency list).
"""

from __future__ import annotations

import json
from typing import Any

PROTOCOL_VERSION = "v0.9.1"


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
