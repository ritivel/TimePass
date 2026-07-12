"""Gemini provider (Flash-Lite) with Google Search grounding.

Grounding notes (verified July 2026):
- `google_search` tool is INCOMPATIBLE with `response_mime_type: application/json`
  — so JSON is requested via the prompt and parsed leniently downstream
  (A2UI is prompt-first anyway; llm/__init__.py owns the robustness stack).
- The model decides per-query whether to search; sources arrive in
  grounding_metadata on the response candidates.
- Economics: Flash-Lite includes 1,500 free grounded prompts/day, then
  ~$14/1k search queries — fine for dev/beta; revisit selective grounding
  before scale (PROGRESS.md).
"""

from __future__ import annotations

import asyncio
import logging
import os
from collections.abc import AsyncIterator
from urllib.parse import urlparse

from .base import Chunk, Final, Provider, Source, Turn

log = logging.getLogger(__name__)

MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite")
# 503 UNAVAILABLE ("high demand") is Google-side capacity, not rate limiting —
# no tier eliminates it. Flash sits in a separate capacity pool from
# Flash-Lite, so it makes a cheap failures-only fallback (PROGRESS.md).
FALLBACK_MODEL = os.environ.get("GEMINI_FALLBACK_MODEL", "gemini-2.5-flash")


def _extract_sources(candidates) -> list[Source]:
    """Pulls web sources from grounding metadata, deduped by URL."""
    sources: dict[str, Source] = {}
    for candidate in candidates or []:
        metadata = getattr(candidate, "grounding_metadata", None)
        for chunk in getattr(metadata, "grounding_chunks", None) or []:
            web = getattr(chunk, "web", None)
            if web is None or not getattr(web, "uri", None):
                continue
            title = getattr(web, "title", None) or ""
            domain = getattr(web, "domain", None) or ""
            if not domain:
                # title is often the bare domain; fall back to parsing the uri
                domain = title if "." in title and " " not in title else urlparse(web.uri).netloc
            sources[web.uri] = Source(title=title or domain, url=web.uri, domain=domain)
    return list(sources.values())[:5]


class GeminiProvider(Provider):
    name = "gemini"

    def available(self) -> bool:
        return bool(os.environ.get("GEMINI_API_KEY"))

    def _client(self):
        from google import genai  # lazy: mock mode needs no network deps

        return genai.Client(api_key=os.environ["GEMINI_API_KEY"])

    @staticmethod
    def _contents(turns: list[Turn]) -> list[dict]:
        return [
            {"role": "user" if t.role == "user" else "model", "parts": [{"text": t.text}]}
            for t in turns
        ]

    @staticmethod
    def _config(system: str, grounded: bool) -> dict:
        config: dict = {"system_instruction": system, "temperature": 0.4}
        if grounded:
            # NOTE: response_mime_type must stay off when tools are present.
            config["tools"] = [{"google_search": {}}]
        else:
            config["response_mime_type"] = "application/json"
        return config

    # 5xx recovery ladder: retry the primary after a short backoff (spikes
    # usually clear in seconds), then try the fallback model once.
    _ATTEMPTS = ((MODEL, 0.0), (MODEL, 1.5), (FALLBACK_MODEL, 0.0))

    async def stream(
        self, system: str, turns: list[Turn], *, grounded: bool = True
    ) -> AsyncIterator[Chunk | Final]:
        from google.genai import errors as genai_errors

        client = self._client()
        for attempt, (model, backoff) in enumerate(self._ATTEMPTS):
            try:
                if backoff:
                    await asyncio.sleep(backoff)
                buffer = ""
                candidates = []
                stream = await client.aio.models.generate_content_stream(
                    model=model,
                    contents=self._contents(turns),
                    config=self._config(system, grounded),
                )
                async for chunk in stream:
                    if chunk.text:
                        buffer += chunk.text
                        yield Chunk(chunk.text)
                    if chunk.candidates:
                        candidates = chunk.candidates
                yield Final(buffer, _extract_sources(candidates))
                return
            except genai_errors.ServerError:
                if attempt + 1 < len(self._ATTEMPTS):
                    next_model = self._ATTEMPTS[attempt + 1][0]
                    log.info("Gemini 5xx on %s, retrying via %s", model, next_model)
                    continue
                raise

    async def complete(
        self, system: str, turns: list[Turn], *, grounded: bool = False
    ) -> Final:
        from google.genai import errors as genai_errors

        client = self._client()
        for attempt, (model, backoff) in enumerate(self._ATTEMPTS):
            try:
                if backoff:
                    await asyncio.sleep(backoff)
                response = await client.aio.models.generate_content(
                    model=model,
                    contents=self._contents(turns),
                    config=self._config(system, grounded),
                )
                return Final(response.text or "", _extract_sources(response.candidates))
            except genai_errors.ServerError:
                if attempt + 1 < len(self._ATTEMPTS):
                    next_model = self._ATTEMPTS[attempt + 1][0]
                    log.info("Gemini 5xx on %s, retrying via %s", model, next_model)
                    continue
                raise
        raise RuntimeError("unreachable")
