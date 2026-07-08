"""TimePass orchestrator API.

POST /v1/query {query, lang?, surfaceId?} → NDJSON stream:
  1. {"timepass": {caption, lang, surfaceId}}     TTS caption (app-level line)
  2. {"version": "v0.9.1", "createSurface": ...}   A2UI messages ↓
  3. {"version": "v0.9.1", "updateDataModel": ...}
  4. {"version": "v0.9.1", "updateComponents": ...}

Hero categories are template-composed and adapter-fed (deterministic, cached);
only the generic tier calls the LLM. Every surface passes the catalog
validator before shipping — fail closed.
"""

from __future__ import annotations

import logging
import uuid
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel, Field

from . import a2ui, llm, templates
from .adapters import cricket, panchang, weather
from .router import Category, route
from .validator import SurfaceValidationError, catalog_id, validate_surface

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("timepass")

app = FastAPI(title="TimePass Orchestrator", version="0.1.0")


class QueryRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    lang: Literal["en", "hi", "te"] = "en"
    surfaceId: str | None = None


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True, "catalogId": catalog_id()}


@app.post("/v1/query")
async def query(req: QueryRequest) -> StreamingResponse:
    surface_id = req.surfaceId or f"s_{uuid.uuid4().hex[:12]}"
    category = route(req.query)
    log.info("query lang=%s category=%s %r", req.lang, category.value, req.query[:80])

    if category is Category.CRICKET:
        data = await cricket.get_live_match(req.query, req.lang)
        caption, components, data_model = templates.cricket_surface(data, req.lang)
    elif category is Category.PANCHANG:
        data = await panchang.get_daily_panchang(req.query, req.lang)
        caption, components, data_model = templates.panchang_surface(data, req.lang)
    elif category is Category.WEATHER:
        data = await weather.get_weather(req.query, req.lang)
        caption, components, data_model = templates.weather_surface(data, req.lang)
    elif category is Category.AQI:
        data = await weather.get_aqi(req.query, req.lang)
        caption, components, data_model = templates.aqi_surface(data, req.lang)
    else:
        caption, components, data_model = await llm.generate_generic(req.query, req.lang)

    # Fail closed: a hero template failing validation is a server bug, never
    # something to ship. (Generic-tier LLM output is validated inside llm.py
    # and degrades gracefully there.)
    try:
        validate_surface(components)
    except SurfaceValidationError as e:
        log.error("surface validation failed (%s): %s", category.value, e.errors)
        raise HTTPException(status_code=500, detail={"errors": e.errors}) from e

    body = a2ui.ndjson(
        a2ui.caption_message(surface_id, caption, req.lang),
        a2ui.create_surface(surface_id, catalog_id()),
        a2ui.update_data_model(surface_id, data_model),
        a2ui.update_components(surface_id, components),
    )

    async def stream():
        yield body

    return StreamingResponse(stream(), media_type="application/x-ndjson")


@app.get("/", response_class=PlainTextResponse)
async def index() -> str:
    return "TimePass orchestrator. POST /v1/query {query, lang}\n"
