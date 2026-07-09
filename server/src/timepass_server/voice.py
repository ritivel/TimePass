"""Sarvam voice layer: ASR (Saaras v3) and TTS (Bulbul v3).

The key stays server-side (SSM /shared/sarvam-api-key → SARVAM_API_KEY);
the app talks to /v1/asr and /v1/tts on the orchestrator.

Verified against the live API 2026-07-09:
- POST /speech-to-text  multipart {model, mode, file}  → {transcript,
  language_code, language_probability} — auto language detection means the
  app doesn't need the user's language up front for voice queries.
- POST /text-to-speech  json {text, target_language_code, model}
  → {audios: [base64 wav]}. Numbers >4 digits need commas for correct
  pronunciation (LLM captions already use ₹78,450-style formatting).
- Saarika is deprecated; Saaras v3 with mode=transcribe replaces it.
"""

from __future__ import annotations

import base64
import os
from collections import OrderedDict

import httpx

SARVAM_BASE = "https://api.sarvam.ai"
ASR_MODEL = os.environ.get("SARVAM_ASR_MODEL", "saaras:v3")
TTS_MODEL = os.environ.get("SARVAM_TTS_MODEL", "bulbul:v3")

# BCP-47 codes for the app's languages; STT replies in the same form.
_TO_BCP47 = {"en": "en-IN", "hi": "hi-IN", "te": "te-IN"}
_FROM_BCP47 = {v: k for k, v in _TO_BCP47.items()}

# Test seam: inject an httpx.MockTransport here.
_transport: httpx.AsyncBaseTransport | None = None

# Captions repeat (degrade text, greetings) — a tiny LRU keeps re-synthesis
# cost at ₹0 for those. TTS is priced per character.
_TTS_CACHE_MAX = 128
_tts_cache: OrderedDict[tuple[str, str], bytes] = OrderedDict()


class VoiceError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


def available() -> bool:
    return bool(os.environ.get("SARVAM_API_KEY"))


def _client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=SARVAM_BASE,
        headers={"api-subscription-key": os.environ["SARVAM_API_KEY"]},
        timeout=30.0,
        transport=_transport,
    )


async def transcribe(audio: bytes, content_type: str = "audio/wav") -> dict:
    """Audio (≤30s; wav/mp3/aac/flac/ogg) → {"transcript", "lang"}.

    "lang" is the detected app language code (en/hi/te), falling back to
    "en" for anything outside the supported set.
    """
    async with _client() as client:
        response = await client.post(
            "/speech-to-text",
            data={"model": ASR_MODEL, "mode": "transcribe"},
            files={"file": ("query.wav", audio, content_type)},
        )
    if response.status_code != 200:
        raise VoiceError(response.status_code, f"sarvam asr: {response.text[:200]}")
    payload = response.json()
    return {
        "transcript": payload.get("transcript", ""),
        "lang": _FROM_BCP47.get(payload.get("language_code", ""), "en"),
    }


async def synthesize(text: str, lang: str) -> bytes:
    """Caption text → spoken WAV bytes (Bulbul v3, ≤2500 chars)."""
    key = (text, lang)
    if key in _tts_cache:
        _tts_cache.move_to_end(key)
        return _tts_cache[key]
    async with _client() as client:
        response = await client.post(
            "/text-to-speech",
            json={
                "text": text[:2500],
                "target_language_code": _TO_BCP47.get(lang, "en-IN"),
                "model": TTS_MODEL,
            },
        )
    if response.status_code != 200:
        raise VoiceError(response.status_code, f"sarvam tts: {response.text[:200]}")
    audios = response.json().get("audios") or []
    if not audios:
        raise VoiceError(502, "sarvam tts: empty audio response")
    wav = base64.b64decode(audios[0])
    _tts_cache[key] = wav
    while len(_tts_cache) > _TTS_CACHE_MAX:
        _tts_cache.popitem(last=False)
    return wav
