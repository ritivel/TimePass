"""M0 acceptance tests (COMPONENT_CATALOG.md §11).

Scripted queries across all hero categories and all three languages must
produce catalog-valid A2UI streams; off-catalog and rule-breaking surfaces
must fail closed.
"""

import json

import httpx
import pytest

from timepass_server.main import app
from timepass_server.router import Category, route
from timepass_server.validator import SurfaceValidationError, validate_surface


@pytest.fixture
async def client():
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


def parse_ndjson(text: str) -> list[dict]:
    return [json.loads(line) for line in text.strip().splitlines()]


# ── routing ────────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    ("query", "category"),
    [
        ("ind vs aus score", Category.CRICKET),
        ("आज का पंचांग", Category.PANCHANG),
        ("kal baarish hogi kya", Category.WEATHER),
        ("delhi air quality", Category.AQI),
        ("హైదరాబాద్ వాతావరణం", Category.WEATHER),
        ("write a leave letter to my manager", Category.GENERIC),
        # regression: " vs " must not hijack generic comparisons
        ("mutual funds vs FD which is better", Category.GENERIC),
    ],
)
def test_routing(query: str, category: Category):
    assert route(query) is category


# ── the 10 scripted M0 queries ─────────────────────────────────────────────

SCRIPTED = [
    ("ind vs aus live score", "en", "CricketLiveScore"),
    ("क्रिकेट स्कोर", "hi", "CricketLiveScore"),
    ("స్కోరు చెప్పు", "te", "CricketLiveScore"),
    ("aaj ka panchang", "en", "PanchangCard"),
    ("आज की तिथि", "hi", "PanchangCard"),
    ("రేపటి రాహుకాలం", "te", "PanchangCard"),
    ("hyderabad weather", "en", "WeatherStrip"),
    ("मौसम कैसा है", "hi", "WeatherStrip"),
    ("delhi aqi", "en", "AqiMeter"),
    ("mutual funds kya hote hain", "en", "Markdown"),  # generic tier (mock)
]


@pytest.mark.parametrize(("query", "lang", "expected_component"), SCRIPTED)
async def test_scripted_queries(client, query, lang, expected_component):
    resp = await client.post("/v1/query", json={"query": query, "lang": lang})
    assert resp.status_code == 200
    messages = parse_ndjson(resp.text)

    # exactly one caption extension line, non-empty, right language
    captions = [m["timepass"] for m in messages if "timepass" in m]
    assert len(captions) == 1
    assert captions[0]["caption"]
    assert captions[0]["lang"] == lang

    # A2UI sequence: starts with createSurface, ends with updateComponents
    # (the generic tier streams a placeholder surface in between).
    a2ui_msgs = [m for m in messages if "timepass" not in m]
    kinds = [next(k for k in m if k != "version") for m in a2ui_msgs]
    assert kinds[0] == "createSurface"
    assert kinds[-1] == "updateComponents"
    # v0.9 on the wire (v0.9.1 is a patch of the v0.9 family; genui pins "v0.9")
    assert all(m["version"] == "v0.9" for m in a2ui_msgs)

    surface_id = a2ui_msgs[0]["createSurface"]["surfaceId"]
    assert all(list(m.values())[1]["surfaceId"] == surface_id for m in a2ui_msgs)

    # every updateComponents on the wire must be catalog-valid (fail closed)
    for m in a2ui_msgs:
        if "updateComponents" in m:
            validate_surface(m["updateComponents"]["components"])

    components = a2ui_msgs[-1]["updateComponents"]["components"]
    types = {c["component"] for c in components}
    assert expected_component in types

    # root exists and FollowUpChips is last child
    root = next(c for c in components if c["id"] == "root")
    assert root["component"] == "Column"
    chips = [c for c in components if c["component"] == "FollowUpChips"]
    if chips:
        assert root["children"][-1] == chips[0]["id"]


async def test_surface_id_passthrough(client):
    resp = await client.post(
        "/v1/query", json={"query": "delhi aqi", "lang": "en", "surfaceId": "test_surface"}
    )
    messages = parse_ndjson(resp.text)
    assert messages[1]["createSurface"]["surfaceId"] == "test_surface"


# ── fail-closed validator ──────────────────────────────────────────────────

def test_rejects_off_catalog_component():
    with pytest.raises(SurfaceValidationError, match="unknown component"):
        validate_surface(
            [
                {"id": "root", "component": "Column", "children": ["evil"]},
                {"id": "evil", "component": "WebView", "url": "https://x.example"},
            ]
        )


def test_rejects_cricket_without_lag_notice():
    score = {
        "id": "score",
        "component": "CricketLiveScore",
        "matchId": "m1",
        "matchTitle": "IND vs AUS",
        "statusText": "IND batting",
        "teams": [
            {"name": "India", "shortName": "IND"},
            {"name": "Australia", "shortName": "AUS"},
        ],
        "lagSeconds": 300,
        "updatedAtText": "now",
    }
    with pytest.raises(SurfaceValidationError, match="Notice"):
        validate_surface(
            [{"id": "root", "component": "Column", "children": ["score"]}, score]
        )


def test_rejects_bad_prop_values():
    with pytest.raises(SurfaceValidationError, match="aqi_card"):
        validate_surface(
            [
                {"id": "root", "component": "Column", "children": ["aqi_card"]},
                {
                    "id": "aqi_card",
                    "component": "AqiMeter",
                    "locationName": "Delhi",
                    "aqi": 287,
                    "category": "apocalyptic",  # not in enum
                    "categoryText": "??",
                    "updatedAtText": "now",
                    "healthAdviceText": "stay in",
                },
            ]
        )


def test_rejects_dangling_child_ref():
    with pytest.raises(SurfaceValidationError, match="does not exist"):
        validate_surface(
            [{"id": "root", "component": "Column", "children": ["ghost"]}]
        )


def test_rejects_missing_root():
    with pytest.raises(SurfaceValidationError, match="root"):
        validate_surface([{"id": "a", "component": "Divider"}])


# ── LLM output normalization ───────────────────────────────────────────────

def test_flatten_nested_llm_output():
    from timepass_server.a2ui import flatten_components

    nested = [
        {
            "id": "root",
            "component": "Column",
            "children": [
                {"id": "title", "component": "Text", "variant": "h2", "text": "Hi"},
                {"component": "Markdown", "text": "body"},  # no id → synthesized
                "chips",  # already a ref
            ],
        },
        {
            "id": "chips",
            "component": "FollowUpChips",
            "suggestions": [{"label": "a", "query": "b"}, {"label": "c", "query": "d"}],
        },
    ]
    flat = flatten_components(nested)
    root = next(c for c in flat if c["id"] == "root")
    assert root["children"][0] == "title"
    assert root["children"][2] == "chips"
    assert all(isinstance(ref, str) for ref in root["children"])
    validate_surface(flat)  # normalized output must be catalog-valid


def test_llm_output_normalization():
    from timepass_server.llm import _parse_and_validate

    # keyed cells (LLM shape mistake) + trailing garbage after the JSON object
    raw = json.dumps({
        "caption": "Comparison ready.",
        "components": [
            {"id": "root", "component": "Column", "children": ["cmp"]},
            {
                "id": "cmp",
                "component": "ComparisonTable",
                "columns": [{"key": "a", "label": "A"}, {"key": "b", "label": "B"}],
                "rows": [
                    {"label": "Price", "cells": [
                        {"key": "b", "value": "₹200"}, {"key": "a", "value": "₹100"},
                    ]},
                ],
            },
        ],
        "dataModel": {},
    }) + "\ntrailing junk"
    caption, components, _ = _parse_and_validate(raw)
    assert caption == "Comparison ready."
    cmp_table = next(c for c in components if c["component"] == "ComparisonTable")
    # keyed cells re-ordered to match column order
    assert cmp_table["rows"][0]["cells"] == ["₹100", "₹200"]


def test_normalizer_prunes_hallucinated_props():
    from timepass_server.llm import _parse_and_validate

    raw = json.dumps({
        "caption": "Done.",
        "components": [
            {"id": "root", "component": "Column", "children": ["chips"]},
            {
                "id": "chips",
                "component": "FollowUpChips",
                "event": {"name": "made_up"},  # hallucinated — must be pruned
                "suggestions": [
                    {"label": "a", "query": "b"}, {"label": "c", "query": "d"},
                ],
            },
        ],
    })
    _, components, _ = _parse_and_validate(raw)  # must not raise
    chips = next(c for c in components if c["component"] == "FollowUpChips")
    assert "event" not in chips
