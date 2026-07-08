"""TimePass orchestrator API.

POST /v1/query {query, lang?, surfaceId?} → NDJSON stream of A2UI messages
(createSurface / updateDataModel / updateComponents) plus one app-level
{"timepass": {caption, lang, surfaceId}} TTS-caption line.

Hero categories are template-composed and adapter-fed (deterministic, cached,
sent atomically). The generic tier streams progressively: placeholder surface
→ early caption → validated final surface. Every surface passes the catalog
validator before shipping — fail closed.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel, Field

from . import a2ui, llm, templates
from .adapters import aqi, cricket, panchang, weather
from .router import Category, route
from .validator import SurfaceValidationError, catalog_id, validate_surface

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("timepass")

app = FastAPI(title="TimePass Orchestrator", version="0.1.0")

# Dev-only: Flutter web runs on a random localhost port. Lock down before beta.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class HistoryTurn(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=500)


class QueryRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    lang: Literal["en", "hi", "te"] = "en"
    surfaceId: str | None = None
    # Recent conversation turns (queries + answer captions) so follow-ups
    # like "what about short term?" carry context. Client-supplied keeps the
    # server stateless; the llm layer caps at the last 12.
    history: list[HistoryTurn] = Field(default_factory=list, max_length=24)


# Surfaces eligible for live refresh: surface_id -> (category, lang, expires_at).
# In-memory is fine for M0 (single process); a real deployment shares this.
LIVE_TTL_SECONDS = int(os.environ.get("LIVE_TTL_SECONDS", "300"))
LIVE_REFRESH_SECONDS = float(os.environ.get("LIVE_REFRESH_SECONDS", "8"))
_live_surfaces: dict[str, tuple[str, str, float]] = {}


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True, "catalogId": catalog_id()}


@app.post("/v1/query")
async def query(req: QueryRequest) -> StreamingResponse:
    surface_id = req.surfaceId or f"s_{uuid.uuid4().hex[:12]}"
    category = route(req.query)
    log.info("query lang=%s category=%s %r", req.lang, category.value, req.query[:80])

    if category is Category.GENERIC:
        # Progressive: placeholder surface immediately, caption as soon as it
        # parses out of the LLM stream, validated final surface at the end.
        return StreamingResponse(
            llm.generate_generic_stream(
                req.query, req.lang, surface_id,
                [t.model_dump() for t in req.history],
            ),
            media_type="application/x-ndjson",
        )

    live = False
    if category is Category.CRICKET:
        data = await cricket.get_live_match(req.query, req.lang)
        caption, components, data_model = templates.cricket_surface(data, req.lang)
        _live_surfaces[surface_id] = ("cricket", req.lang, time.monotonic() + LIVE_TTL_SECONDS)
        live = True
    elif category is Category.PANCHANG:
        data = await panchang.get_daily_panchang(req.query, req.lang)
        caption, components, data_model = templates.panchang_surface(data, req.lang)
    elif category is Category.WEATHER:
        data = await weather.get_weather(req.query, req.lang)
        caption, components, data_model = templates.weather_surface(data, req.lang)
    else:  # Category.AQI
        data = await aqi.get_aqi(req.query, req.lang)
        caption, components, data_model = templates.aqi_surface(data, req.lang)

    # Fail closed: a hero template failing validation is a server bug, never
    # something to ship. (Generic-tier surfaces are validated inside
    # generate_generic_stream and degrade gracefully there.)
    try:
        validate_surface(components)
    except SurfaceValidationError as e:
        log.error("surface validation failed (%s): %s", category.value, e.errors)
        raise HTTPException(status_code=500, detail={"errors": e.errors}) from e

    body = a2ui.ndjson(
        a2ui.caption_message(surface_id, caption, req.lang, live=live),
        a2ui.create_surface(surface_id, catalog_id()),
        a2ui.update_data_model(surface_id, data_model),
        a2ui.update_components(surface_id, components),
    )

    async def stream():
        yield body

    return StreamingResponse(stream(), media_type="application/x-ndjson")


@app.get("/v1/live/{surface_id}")
async def live(surface_id: str) -> StreamingResponse:
    """Pushes updateDataModel refreshes for a live surface (NDJSON stream).

    The A2UI data-model bindings mean the client re-renders without any
    component regeneration — this is the ₹-free half of "live scores".
    Stream ends at TTL; the client may resubscribe on user intent.
    """
    entry = _live_surfaces.get(surface_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="not a live surface (or expired)")
    category, lang, expires_at = entry

    async def stream():
        try:
            while time.monotonic() < expires_at:
                await asyncio.sleep(LIVE_REFRESH_SECONDS)
                if category == "cricket":
                    data = await cricket.get_live_match("", lang)
                    yield a2ui.ndjson(a2ui.update_data_model(surface_id, {"cricket": data}))
        finally:
            _live_surfaces.pop(surface_id, None)

    return StreamingResponse(stream(), media_type="application/x-ndjson")


@app.get("/", response_class=PlainTextResponse)
async def index() -> str:
    return "TimePass orchestrator. POST /v1/query {query, lang}\n"
