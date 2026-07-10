"""Server-side surface validator — the fail-closed gate before anything ships.

Checks every component instance against the generated catalog schema
(catalog/dist/catalog.json) plus the structural composition rules from
COMPONENT_CATALOG.md §5 that a JSON Schema can't express (R1, R3, R4, R6).
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

import jsonschema

CATALOG_PATH = Path(__file__).resolve().parents[3] / "catalog" / "dist" / "catalog.json"

HERO_COMPONENTS = {"CricketLiveScore", "PanchangCard", "WeatherStrip", "AqiMeter"}
ACTION_COMPONENTS = {"UpiPayButton", "AffiliateCta", "ConsultReferralCard", "DeepLinkCard"}
CONTAINER_CHILDREN = {"Row", "Column", "List"}
CONTAINER_CHILD = {"Card", "Button"}
URL_RE = re.compile(r"https?://|upi://|intent://", re.IGNORECASE)

MAX_COMPONENTS = 40
MAX_DEPTH = 4


class SurfaceValidationError(Exception):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("; ".join(errors))


@lru_cache(maxsize=1)
def _catalog() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text())


def catalog_id() -> str:
    return _catalog()["catalogId"]


def known_props(component_type: str) -> set[str] | None:
    """Top-level prop names for a component, or None if unknown type."""
    schema = _catalog()["components"].get(component_type)
    if schema is None:
        return None
    return set(schema.get("properties", {}))


def validate_surface(components: list[dict[str, Any]]) -> None:
    """Raises SurfaceValidationError with all findings; returns None when valid."""
    errors: list[str] = []
    schemas = _catalog()["components"]

    by_id: dict[str, dict[str, Any]] = {}
    for comp in components:
        cid, ctype = comp.get("id"), comp.get("component")
        if not cid or not isinstance(cid, str):
            errors.append(f"component missing id: {json.dumps(comp)[:80]}")
            continue
        if cid in by_id:
            errors.append(f"duplicate id: {cid}")
        by_id[cid] = comp
        if ctype not in schemas:
            errors.append(f"{cid}: unknown component {ctype!r} (not in catalog)")
            continue
        for err in jsonschema.Draft202012Validator(schemas[ctype]).iter_errors(comp):
            errors.append(f"{cid}: {err.message} at {'/'.join(map(str, err.path)) or '<root>'}")

    if errors:
        raise SurfaceValidationError(errors)

    if len(components) > MAX_COMPONENTS:
        errors.append(f"{len(components)} components exceeds max {MAX_COMPONENTS}")

    root = by_id.get("root")
    if root is None:
        errors.append('no component with id "root"')
    elif root["component"] != "Column":
        errors.append(f'root must be a Column, got {root["component"]}')

    # child references + reachability + depth
    def children_of(comp: dict[str, Any]) -> list[str]:
        if comp["component"] in CONTAINER_CHILDREN:
            return list(comp.get("children") or [])
        if comp["component"] in CONTAINER_CHILD:
            child = comp.get("child")
            return [child] if child else []
        return []

    for comp in components:
        for ref in children_of(comp):
            if ref not in by_id:
                errors.append(f'{comp["id"]}: child ref {ref!r} does not exist')

    if root is not None and not errors:
        seen: set[str] = set()
        stack = [("root", 1)]
        while stack:
            cid, depth = stack.pop()
            if cid in seen:
                errors.append(f"cycle involving {cid}")
                break
            seen.add(cid)
            if depth > MAX_DEPTH:
                errors.append(f"{cid}: nesting depth {depth} exceeds max {MAX_DEPTH}")
                continue
            stack.extend((ref, depth + 1) for ref in children_of(by_id[cid]))
        orphans = set(by_id) - seen
        if orphans and not errors:
            errors.append(f"unreachable components: {sorted(orphans)}")

    types = [c["component"] for c in components]

    def carries_literal_url(value: Any) -> bool:
        if isinstance(value, str):
            return bool(URL_RE.search(value))
        if isinstance(value, dict):
            return any(carries_literal_url(v) for v in value.values())
        if isinstance(value, list):
            return any(carries_literal_url(v) for v in value)
        return False

    # M0 generic buttons are internal UI actions only. External/deep links are
    # trusted surfaces: SourceChips (search metadata) or future server-issued
    # action components with signed URLs. The model must not fabricate them.
    for comp in components:
        if comp["component"] == "Button" and carries_literal_url(comp.get("action")):
            errors.append(
                f"{comp['id']}: Button action cannot carry literal URLs; "
                "use SourceChips or server-issued action components"
            )

    # R4: hero limits
    hero_count = sum(1 for t in types if t in HERO_COMPONENTS)
    if hero_count > 2:
        errors.append(f"{hero_count} hero components exceeds max 2 (R4)")

    # R5: at most one action component
    action_count = sum(1 for t in types if t in ACTION_COMPONENTS)
    if action_count > 1:
        errors.append(f"{action_count} action components exceeds max 1 (R5)")

    # R6: cricket lag disclosure
    if "CricketLiveScore" in types:
        has_legal = any(
            c["component"] == "Notice" and c.get("variant") == "legal" for c in components
        )
        if not has_legal:
            errors.append("CricketLiveScore requires a Notice(variant: legal) on the surface (R6)")

    # R1: FollowUpChips, when present, is the last root child
    if root is not None and "FollowUpChips" in types:
        root_children = root.get("children") or []
        chips_ids = [c["id"] for c in components if c["component"] == "FollowUpChips"]
        for chips_id in chips_ids:
            if chips_id in root_children and root_children[-1] != chips_id:
                errors.append("FollowUpChips must be the last child of root (R1)")

    if errors:
        raise SurfaceValidationError(errors)
