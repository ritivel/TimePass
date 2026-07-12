"""Generic-tier streaming behaviors: grounded preview, needsSearch
escalation, and grounded-text preservation on compose failure.

A scripted fake provider drives generate_generic_stream; assertions run on
the NDJSON the client would receive.
"""

import json

import pytest

import nakul_server.llm as llm
from nakul_server.llm import generate_generic_stream
from nakul_server.llm.base import Chunk, Final, Provider, Source, Turn
from nakul_server.validator import validate_surface

GROUNDED_TEXT = (
    "Gold is trading at ₹78,450 per 10g in Hyderabad today. Prices rose after "
    "the RBI's latest bulletin. Most jewellers quote 22k slightly lower.\n\n"
    "- 24k: ₹78,450\n- 22k: ₹71,900"
)

SURFACE_JSON = json.dumps({
    "caption": "Gold is at seventy-eight thousand rupees today.",
    "components": [
        {"id": "root", "component": "Column", "children": ["answer", "chips"]},
        {"id": "answer", "component": "Markdown", "text": "**24k**: ₹78,450 · **22k**: ₹71,900"},
        {"id": "chips", "component": "FollowUpChips",
         "suggestions": [{"label": "22k trend", "query": "22k gold trend"},
                         {"label": "Silver?", "query": "silver price today"}]},
    ],
    "dataModel": {},
})

SOURCES = [Source(title="Gold rates", url="https://example.com/gold", domain="example.com")]


class ScriptedProvider(Provider):
    """Yields the scripted response for each successive stream() call."""

    name = "scripted"

    def __init__(self, responses: list[tuple[str, list[Source]]]):
        self._responses = responses
        self.calls: list[dict] = []  # {"grounded": bool, "prompt": str}

    def available(self) -> bool:
        return True

    async def stream(self, system, turns, *, grounded=True):
        self.calls.append({"grounded": grounded, "prompt": turns[-1].text})
        text, sources = self._responses[len(self.calls) - 1]
        # stream in smallish chunks to exercise incremental paths
        for i in range(0, len(text), 40):
            yield Chunk(text[i : i + 40])
        yield Final(text, sources)

    async def complete(self, system, turns, *, grounded=False):
        self.calls.append({"grounded": grounded, "prompt": turns[-1].text, "repair": True})
        text, sources = self._responses[len(self.calls) - 1]
        return Final(text, sources)


async def _run(provider, query, lang="en"):
    llm._PROVIDERS["scripted"] = provider
    import os

    os.environ["LLM_PROVIDER"] = "scripted"
    try:
        lines = []
        async for block in generate_generic_stream(query, lang, "s_test"):
            lines.extend(json.loads(l) for l in block.strip().splitlines())
        return lines
    finally:
        del os.environ["LLM_PROVIDER"]
        del llm._PROVIDERS["scripted"]


def _captions(lines):
    return [m["nakul"]["caption"] for m in lines if "nakul" in m]


def _component_updates(lines):
    return [m["updateComponents"]["components"] for m in lines if "updateComponents" in m]


def _data_updates(lines):
    return [m["updateDataModel"]["value"] for m in lines if "updateDataModel" in m]


# ── grounded preview ───────────────────────────────────────────────────────

async def test_grounded_query_streams_markdown_preview_then_composed_surface():
    provider = ScriptedProvider([
        (GROUNDED_TEXT, SOURCES),   # phase 1: search, plain text
        (SURFACE_JSON, []),         # phase 2: compose
    ])
    lines = await _run(provider, "gold price today in hyderabad")

    assert [c["grounded"] for c in provider.calls] == [True, False]

    # caption arrives once, from the grounded text's first sentence
    captions = _captions(lines)
    assert captions == ["Gold is trading at ₹78,450 per 10g in Hyderabad today."]

    updates = _component_updates(lines)
    # placeholder → preview (Markdown bound to /groundedText) → … → final
    preview = next(u for u in updates
                   if any(c.get("id") == "grounded_answer" for c in u))
    bound = next(c for c in preview if c["id"] == "grounded_answer")
    assert bound["text"] == {"path": "/groundedText"}
    validate_surface(preview)

    # the grounded text reached the data model in full
    ground_pushes = [v for v in _data_updates(lines) if "groundedText" in v]
    assert ground_pushes and ground_pushes[-1]["groundedText"] == GROUNDED_TEXT

    # preview index strictly before final surface index (upgrade, not first paint)
    final = updates[-1]
    types = {c["component"] for c in final}
    assert "FollowUpChips" in types
    validate_surface(final)
    # sources from phase 1 attach to the final surface
    assert any(c["component"] == "SourceChips" for c in final)


async def test_grounded_model_may_still_answer_json_directly():
    provider = ScriptedProvider([(SURFACE_JSON, [])])
    lines = await _run(provider, "gold price today")
    assert _captions(lines) == ["Gold is at seventy-eight thousand rupees today."]
    # no preview surface on the wire
    assert not any(
        any(c.get("id") == "grounded_answer" for c in u) for u in _component_updates(lines)
    )
    validate_surface(_component_updates(lines)[-1])


# ── needsSearch escalation ─────────────────────────────────────────────────

async def test_needs_search_escalates_to_grounded_flow():
    provider = ScriptedProvider([
        ('{"needsSearch": true}', []),  # fast path punts
        (GROUNDED_TEXT, SOURCES),       # grounded phase 1
        (SURFACE_JSON, []),             # compose
    ])
    # a freshness-dependent query the keyword gate does NOT catch — the
    # model itself must punt via needsSearch
    lines = await _run(provider, "which iphone does flipkart sell cheapest")

    assert [c["grounded"] for c in provider.calls] == [False, True, False]
    # exactly one caption, from the grounded preview
    assert _captions(lines) == ["Gold is trading at ₹78,450 per 10g in Hyderabad today."]
    final = _component_updates(lines)[-1]
    validate_surface(final)
    assert any(c["component"] == "SourceChips" for c in final)


async def test_ungrounded_json_path_unchanged():
    provider = ScriptedProvider([(SURFACE_JSON, [])])
    lines = await _run(provider, "write a leave letter")
    assert [c["grounded"] for c in provider.calls] == [False]
    assert _captions(lines) == ["Gold is at seventy-eight thousand rupees today."]
    validate_surface(_component_updates(lines)[-1])


# ── compose failure keeps the grounded answer ──────────────────────────────

async def test_compose_failure_finalizes_grounded_text_not_apology():
    bad = '{"caption": "x", "components": [{"id": "root", "component": "Bogus"}], "dataModel": {}}'
    provider = ScriptedProvider([
        (GROUNDED_TEXT, SOURCES),  # phase 1 fine
        (bad, []),                 # compose invalid
        (bad, []),                 # repair retry also invalid
    ])
    lines = await _run(provider, "gold price today")

    final = _component_updates(lines)[-1]
    validate_surface(final)
    markdown = next(c for c in final if c["component"] == "Markdown")
    assert markdown["text"] == GROUNDED_TEXT  # not the degrade apology
    assert any(c["component"] == "SourceChips" for c in final)

    # repair was attempted against the compose prompt, not the raw query
    assert provider.calls[-1].get("repair") is True
    assert "web search already produced" in provider.calls[-1]["prompt"]


# ── needsData: the unified data path ───────────────────────────────────────

AQI_DATA = {
    "locationName": "Delhi", "aqi": 178, "category": "moderate",
    "categoryText": "Moderate", "dominantPollutant": "PM2.5",
    "stationName": "12 stations", "updatedAtText": "Updated 10:00 IST",
    "healthAdviceText": "Sensitive groups should limit outdoor exertion.",
}

AQI_SURFACE_JSON = json.dumps({
    "caption": "Air quality in Delhi is moderate at 178.",
    "components": [
        {"id": "root", "component": "Column", "children": ["aqi", "chips"]},
        {"id": "aqi", "component": "AqiMeter",
         "locationName": {"path": "/aqi/locationName"},
         "aqi": {"path": "/aqi/aqi"},
         "category": {"path": "/aqi/category"},
         "categoryText": {"path": "/aqi/categoryText"},
         "dominantPollutant": {"path": "/aqi/dominantPollutant"},
         "stationName": {"path": "/aqi/stationName"},
         "updatedAtText": {"path": "/aqi/updatedAtText"},
         "healthAdviceText": {"path": "/aqi/healthAdviceText"}},
        {"id": "chips", "component": "FollowUpChips",
         "suggestions": [{"label": "Tomorrow?", "query": "delhi aqi tomorrow"},
                         {"label": "Mumbai", "query": "mumbai air quality"}]},
    ],
    "dataModel": {},
})


async def test_needs_data_fetches_adapter_and_binds_data_model(monkeypatch):
    fetched = {}

    async def fake_aqi(query, lang):
        fetched["query"] = query
        fetched["lang"] = lang
        return AQI_DATA

    monkeypatch.setitem(llm._DATA_SOURCES, "aqi", fake_aqi)
    provider = ScriptedProvider([
        ('{"needsData": {"source": "aqi"}}', []),  # fast path requests data
        (AQI_SURFACE_JSON, []),                    # compose from data
    ])
    lines = await _run(provider, "is the air very polluted in delhi")

    # adapter got the raw query (adapters parse the city themselves)
    assert fetched == {"query": "is the air very polluted in delhi", "lang": "en"}
    # both LLM calls ungrounded — no search spent
    assert [c["grounded"] for c in provider.calls] == [False, False]
    # compose prompt carried the adapter data
    assert '"aqi": 178' in provider.calls[-1]["prompt"]

    final = _component_updates(lines)[-1]
    validate_surface(final)
    assert any(c["component"] == "AqiMeter" for c in final)
    # the adapter data shipped in the data model for the {path} bindings
    final_dm = _data_updates(lines)[-1]
    assert final_dm["aqi"] == AQI_DATA
    assert _captions(lines) == ["Air quality in Delhi is moderate at 178."]


async def test_needs_data_unknown_source_escalates_to_search(monkeypatch):
    provider = ScriptedProvider([
        ('{"needsData": {"source": "stocks"}}', []),  # not a real source
        (GROUNDED_TEXT, SOURCES),                     # grounded phase 1
        (SURFACE_JSON, []),                           # compose
    ])
    lines = await _run(provider, "how is the sensex doing")
    assert [c["grounded"] for c in provider.calls] == [False, True, False]
    validate_surface(_component_updates(lines)[-1])


async def test_needs_data_compose_failure_repairs_with_data_prompt(monkeypatch):
    async def fake_aqi(query, lang):
        return AQI_DATA

    monkeypatch.setitem(llm._DATA_SOURCES, "aqi", fake_aqi)
    bad = '{"caption": "x", "components": [{"id": "root", "component": "Bogus"}], "dataModel": {}}'
    provider = ScriptedProvider([
        ('{"needsData": {"source": "aqi"}}', []),
        (bad, []),               # compose invalid
        (AQI_SURFACE_JSON, []),  # repair succeeds
    ])
    lines = await _run(provider, "delhi pollution level")
    assert provider.calls[-1].get("repair") is True
    assert '"aqi": 178' in provider.calls[-1]["prompt"]  # repair keeps the data prompt
    final = _component_updates(lines)[-1]
    validate_surface(final)
    assert _data_updates(lines)[-1]["aqi"] == AQI_DATA


async def test_empty_model_output_degrades_politely():
    provider = ScriptedProvider([("", []), ("", []), ("", [])])
    lines = await _run(provider, "gold price today")
    final = _component_updates(lines)[-1]
    validate_surface(final)
    markdown = next(c for c in final if c["component"] == "Markdown")
    assert "try again" in markdown["text"]
