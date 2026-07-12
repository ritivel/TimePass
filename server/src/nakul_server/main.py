"""Nakul orchestrator API.

POST /v1/query {query, lang?, surfaceId?} → NDJSON stream of A2UI messages
(createSurface / updateDataModel / updateComponents) plus one app-level
{"nakul": {caption, lang, surfaceId}} TTS-caption line.

Hero categories are template-composed and adapter-fed (deterministic, cached,
sent atomically). The generic tier streams progressively: placeholder surface
→ early caption → validated final surface. Every surface passes the catalog
validator before shipping — fail closed.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import time
import uuid
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, Response, StreamingResponse
from pydantic import BaseModel, Field

from . import a2ui, auth, llm, templates, visuals, voice
from .adapters import aqi, cricket, panchang, weather
from .router import Category, route
from .validator import SurfaceValidationError, catalog_id, validate_surface

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("nakul")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    missing = auth.missing_production_config()
    if missing:
        raise RuntimeError(
            "Authenticated deployment is missing required configuration: "
            + ", ".join(missing)
        )
    yield


app = FastAPI(title="Nakul Orchestrator", version="0.1.0", lifespan=lifespan)

_allowed_origins = [
    origin.strip()
    for origin in os.environ.get("NAKUL_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    # Flutter web uses a random localhost port during local development.
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["authorization", "content-type", "x-request-id"],
    expose_headers=["x-request-id"],
)

_request_id_pattern = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


@app.middleware("http")
async def operational_headers(request: Request, call_next):
    supplied_id = request.headers.get("x-request-id", "")
    request_id = (
        supplied_id
        if _request_id_pattern.fullmatch(supplied_id)
        else uuid.uuid4().hex
    )
    started = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        log.exception(
            "request failed id=%s method=%s path=%s",
            request_id,
            request.method,
            request.url.path,
        )
        raise
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    if request.url.path.startswith("/v1/"):
        response.headers.setdefault("Cache-Control", "no-store")
    elapsed_ms = (time.perf_counter() - started) * 1000
    log.info(
        "request id=%s method=%s path=%s status=%d elapsed_ms=%.1f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response


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


class VisualRequest(BaseModel):
    prompt: str = Field(min_length=8, max_length=500)
    aspectRatio: Literal["landscape", "square", "portrait"] = "landscape"


# Surfaces eligible for live refresh:
# surface_id -> (category, lang, expires_at, owner_id).
# In-memory is fine for M0 (single process); a real deployment shares this.
LIVE_TTL_SECONDS = int(os.environ.get("LIVE_TTL_SECONDS", "300"))
LIVE_REFRESH_SECONDS = float(os.environ.get("LIVE_REFRESH_SECONDS", "8"))
_live_surfaces: dict[str, tuple[str, str, float, str]] = {}


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True, "catalogId": catalog_id()}


@app.post("/v1/query")
async def query(
    req: QueryRequest,
    user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> StreamingResponse:
    await auth.enforce_query_quota(user)
    surface_id = req.surfaceId or f"s_{uuid.uuid4().hex[:12]}"
    category = route(req.query)
    log.info(
        "query user=%s lang=%s category=%s chars=%d",
        user.id[:8],
        req.lang,
        category.value,
        len(req.query),
    )

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
        _live_surfaces[surface_id] = (
            "cricket",
            req.lang,
            time.monotonic() + LIVE_TTL_SECONDS,
            user.id,
        )
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
async def live(
    surface_id: str,
    user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> StreamingResponse:
    """Pushes updateDataModel refreshes for a live surface (NDJSON stream).

    The A2UI data-model bindings mean the client re-renders without any
    component regeneration — this is the ₹-free half of "live scores".
    Stream ends at TTL; the client may resubscribe on user intent.
    """
    entry = _live_surfaces.get(surface_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="not a live surface (or expired)")
    category, lang, expires_at, owner_id = entry
    if owner_id != user.id:
        # Avoid revealing whether another user's live surface exists.
        raise HTTPException(status_code=404, detail="not a live surface (or expired)")

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


# ── voice (Sarvam) ──────────────────────────────────────────────────────────


class TtsRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2500)
    lang: Literal["en", "hi", "te"] = "en"


@app.post("/v1/asr")
async def asr(
    file: UploadFile,
    _user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> dict:
    """Spoken query (≤30s wav/mp3/aac/flac/ogg) → {"transcript", "lang"}.

    Language is auto-detected by Saaras, so the app can route the query in
    whatever language was spoken.
    """
    if not voice.available():
        raise HTTPException(status_code=503, detail="voice not configured")
    audio = await file.read()
    if not audio:
        raise HTTPException(status_code=400, detail="empty audio")
    if len(audio) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="audio file too large")
    try:
        return await voice.transcribe(audio, file.content_type or "audio/wav")
    except voice.VoiceError as e:
        raise HTTPException(status_code=502, detail=e.detail) from e


@app.post("/v1/tts")
async def tts(
    req: TtsRequest,
    _user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> Response:
    """Caption text → spoken audio (WAV)."""
    if not voice.available():
        raise HTTPException(status_code=503, detail="voice not configured")
    try:
        wav = await voice.synthesize(req.text, req.lang)
    except voice.VoiceError as e:
        raise HTTPException(status_code=502, detail=e.detail) from e
    return Response(content=wav, media_type="audio/wav")


@app.post("/v1/visual")
async def visual(
    req: VisualRequest,
    _user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> Response:
    """Generate one style-locked image used by a GeneratedVisual component."""
    if not visuals.available():
        raise HTTPException(status_code=503, detail="visual generation not configured")
    try:
        image, mime = await asyncio.wait_for(
            visuals.generate(req.prompt, req.aspectRatio), timeout=75
        )
    except TimeoutError as e:
        raise HTTPException(status_code=504, detail="visual generation timed out") from e
    except visuals.VisualError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
    except Exception as e:
        log.exception("visual generation failed")
        raise HTTPException(status_code=502, detail="visual generation failed") from e
    return Response(
        content=image,
        media_type=mime,
        headers={"Cache-Control": "private, max-age=86400"},
    )


@app.delete("/v1/account", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    user: auth.AuthenticatedUser = Depends(auth.require_user),
) -> Response:
    """Permanently delete the signed-in user and cascaded account data."""
    await auth.delete_user(user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/", response_class=PlainTextResponse)
async def index() -> str:
    return "Nakul orchestrator. POST /v1/query {query, lang}\n"
