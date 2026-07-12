"""M0 acceptance tests (COMPONENT_CATALOG.md §11).

Scripted queries across all hero categories and all three languages must
produce catalog-valid A2UI streams; off-catalog and rule-breaking surfaces
must fail closed.
"""

import json

import httpx
import pytest

from nakul_server.main import app
from nakul_server.router import Category, route
from nakul_server.validator import SurfaceValidationError, validate_surface


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
    captions = [m["nakul"] for m in messages if "nakul" in m]
    assert len(captions) == 1
    assert captions[0]["caption"]
    assert captions[0]["lang"] == lang

    # A2UI sequence: starts with createSurface, ends with updateComponents
    # (the generic tier streams a placeholder surface in between).
    a2ui_msgs = [m for m in messages if "nakul" not in m]
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


def test_rejects_model_fabricated_button_urls():
    with pytest.raises(SurfaceValidationError, match="literal URLs"):
        validate_surface(
            [
                {
                    "id": "root",
                    "component": "Column",
                    "children": ["label", "cta", "chips"],
                },
                {"id": "label", "component": "Text", "text": "Open this"},
                {
                    "id": "cta_label",
                    "component": "Text",
                    "text": "Search web",
                },
                {
                    "id": "cta",
                    "component": "Button",
                    "child": "cta_label",
                    "action": {
                        "event": {
                            "name": "open_url",
                            "context": {"url": "https://example.com"},
                        }
                    },
                },
                {
                    "id": "chips",
                    "component": "FollowUpChips",
                    "suggestions": [
                        {"label": "More", "query": "tell me more"},
                        {"label": "Shorter", "query": "make it shorter"},
                    ],
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


# ── CPCB AQI adapter (no network — canned records) ─────────────────────────

def test_aqi_city_rollup_and_categories():
    from nakul_server.adapters.aqi import category_for, city_from_query, summarize_records

    records = [
        # station A: PM2.5 dominant, AQI 210
        {"station": "A", "pollutant_id": "PM2.5", "avg_value": "210",
         "last_update": "08-07-2026 21:00:00"},
        {"station": "A", "pollutant_id": "CO", "avg_value": "40",
         "last_update": "08-07-2026 21:00:00"},
        # station B: NA row ignored; OZONE 90
        {"station": "B", "pollutant_id": "SO2", "avg_value": "NA",
         "last_update": "08-07-2026 21:00:00"},
        {"station": "B", "pollutant_id": "OZONE", "avg_value": "90",
         "last_update": "08-07-2026 21:00:00"},
    ]
    summary = summarize_records(records)
    assert summary is not None
    assert summary["aqi"] == 150  # mean(210, 90)
    assert summary["dominant"] in ("PM2.5", "OZONE")
    assert summary["stationCount"] == 2

    assert category_for(45) == "good"
    assert category_for(150) == "moderate"
    assert category_for(287) == "poor"
    assert category_for(999) == "severe"

    assert city_from_query("hyderabad ka aqi") == "Hyderabad"
    assert city_from_query("दिल्ली प्रदूषण") == "Delhi"
    assert city_from_query("air quality") == "Delhi"  # default


def test_aqi_all_na_returns_none():
    from nakul_server.adapters.aqi import summarize_records

    assert summarize_records(
        [{"station": "A", "pollutant_id": "SO2", "avg_value": "NA",
          "last_update": "08-07-2026 21:00:00"}]
    ) is None


# ── LLM output normalization ───────────────────────────────────────────────

def test_flatten_nested_llm_output():
    from nakul_server.a2ui import flatten_components

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
    from nakul_server.llm import _parse_and_validate

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


def test_freshness_gate():
    from nakul_server.llm import needs_freshness

    assert needs_freshness("what is the current repo rate in india")
    assert needs_freshness("petrol price today")
    assert needs_freshness("आज की खबर")
    assert needs_freshness("బంగారం ధర ఎంత")
    assert not needs_freshness("explain compound interest simply")
    assert not needs_freshness("write a leave letter to my manager")
    assert not needs_freshness("mutual funds vs FD which is better")


def test_parser_strips_markdown_fences():
    from nakul_server.llm import _parse_and_validate

    raw = '```json\n{"caption": "Hi.", "components": [{"id": "root", "component": "Column", "children": ["a"]}, {"id": "a", "component": "Markdown", "text": "hello"}]}\n```'
    caption, components, _ = _parse_and_validate(raw)
    assert caption == "Hi."
    assert len(components) == 3
    assert components[-1]["component"] == "FollowUpChips"


def test_recipe_is_enriched_with_visual_and_contextual_followups():
    from nakul_server.llm import _parse_and_validate

    raw = json.dumps({
        "caption": "A quick lemon rice dinner for two.",
        "components": [
            {"id": "root", "component": "Column", "children": ["recipe"]},
            {
                "id": "recipe",
                "component": "RecipeCard",
                "title": "Lemon rice",
                "ingredients": [
                    {"name": "Rice", "amount": "2 cups"},
                    {"name": "Lemon", "amount": "2 tbsp"},
                ],
                "steps": [
                    {"title": "Temper", "detail": "Toast the spices."},
                    {"title": "Finish", "detail": "Fold in lemon off heat."},
                ],
            },
        ],
    })
    _, components, _ = _parse_and_validate(raw, "en")
    types = [component["component"] for component in components]
    assert types.count("GeneratedVisual") == 1
    assert types.count("FollowUpChips") == 1
    root = next(component for component in components if component["id"] == "root")
    assert root["children"][-1].startswith("follow_up")
    visual = next(component for component in components if component["component"] == "GeneratedVisual")
    assert "Lemon rice" in visual["prompt"]
    chips = next(component for component in components if component["component"] == "FollowUpChips")
    assert "A quick lemon rice dinner" in chips["suggestions"][0]["query"]


def test_attach_sources_inserts_before_chips():
    from nakul_server.llm import _attach_sources
    from nakul_server.llm.base import Source

    components = [
        {"id": "root", "component": "Column", "children": ["answer", "chips"]},
        {"id": "answer", "component": "Markdown", "text": "x"},
        {"id": "chips", "component": "FollowUpChips",
         "suggestions": [{"label": "a", "query": "b"}, {"label": "c", "query": "d"}]},
    ]
    out = _attach_sources(components, [Source(title="NDTV", url="https://x", domain="ndtv.com")])
    root = next(c for c in out if c["id"] == "root")
    assert root["children"] == ["answer", "web_sources", "chips"]
    validate_surface(out)


async def test_history_accepted(client):
    resp = await client.post("/v1/query", json={
        "query": "what about for short term",
        "lang": "en",
        "history": [
            {"role": "user", "text": "mutual funds vs FD"},
            {"role": "assistant", "text": "Here's a comparison of mutual funds and FDs."},
        ],
    })
    assert resp.status_code == 200


# ── live refresh ───────────────────────────────────────────────────────────

async def test_cricket_marks_surface_live_and_streams_refreshes(client, monkeypatch):
    from nakul_server import main as main_module

    monkeypatch.setattr(main_module, "LIVE_REFRESH_SECONDS", 0.01)
    # Short TTL so the server-side generator ends promptly — under the ASGI
    # test transport a client disconnect does not cancel it, and teardown
    # would otherwise wait out the full 300s TTL.
    monkeypatch.setattr(main_module, "LIVE_TTL_SECONDS", 1)

    resp = await client.post(
        "/v1/query", json={"query": "ind vs aus score", "lang": "en", "surfaceId": "live_t1"}
    )
    messages = parse_ndjson(resp.text)
    ext = next(m["nakul"] for m in messages if "nakul" in m)
    assert ext.get("live") is True

    # subscribe and read two refreshes
    got = []
    async with client.stream("GET", "/v1/live/live_t1") as live_resp:
        assert live_resp.status_code == 200
        async for line in live_resp.aiter_lines():
            if line.strip():
                got.append(json.loads(line))
            if len(got) >= 2:
                break
    assert all("updateDataModel" in m for m in got)
    first = got[0]["updateDataModel"]["value"]["cricket"]
    second = got[1]["updateDataModel"]["value"]["cricket"]
    assert first["teams"][0]["scoreText"] != second["teams"][0]["scoreText"]  # fixture advances


async def test_live_unknown_surface_404(client):
    resp = await client.get("/v1/live/nope")
    assert resp.status_code == 404


def test_normalizer_prunes_hallucinated_props():
    from nakul_server.llm import _parse_and_validate

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
