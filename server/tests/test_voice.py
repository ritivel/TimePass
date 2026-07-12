"""Voice endpoints: Sarvam ASR/TTS behind /v1/asr and /v1/tts.

The Sarvam API is mocked via the voice module's transport seam; the live
contract was verified manually 2026-07-09 (Telugu TTS → STT round-trip).
"""

import base64
import json

import httpx
import pytest

from nakul_server import voice
from nakul_server.main import app

FAKE_WAV = b"RIFF....WAVEfmt fake-audio-bytes"


@pytest.fixture
async def client(monkeypatch):
    monkeypatch.setenv("SARVAM_API_KEY", "test-key")
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
def clear_tts_cache():
    voice._tts_cache.clear()


def _sarvam_mock(monkeypatch, handler):
    monkeypatch.setattr(voice, "_transport", httpx.MockTransport(handler))


# ── /v1/asr ────────────────────────────────────────────────────────────────

async def test_asr_transcribes_and_maps_language(client, monkeypatch):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["path"] = request.url.path
        seen["key"] = request.headers.get("api-subscription-key")
        body = request.read()
        seen["has_audio"] = FAKE_WAV in body
        seen["model"] = b'name="model"' in body and b"saaras:v3" in body
        return httpx.Response(200, json={
            "transcript": "నమస్కారం",
            "language_code": "te-IN",
            "language_probability": 1.0,
        })

    _sarvam_mock(monkeypatch, handler)
    resp = await client.post("/v1/asr", files={"file": ("q.wav", FAKE_WAV, "audio/wav")})
    assert resp.status_code == 200
    assert resp.json() == {"transcript": "నమస్కారం", "lang": "te"}
    assert seen == {"path": "/speech-to-text", "key": "test-key",
                    "has_audio": True, "model": True}


async def test_asr_unknown_language_falls_back_to_en(client, monkeypatch):
    _sarvam_mock(monkeypatch, lambda r: httpx.Response(200, json={
        "transcript": "hello", "language_code": "ta-IN"}))
    resp = await client.post("/v1/asr", files={"file": ("q.wav", FAKE_WAV, "audio/wav")})
    assert resp.json()["lang"] == "en"


async def test_asr_empty_audio_rejected(client):
    resp = await client.post("/v1/asr", files={"file": ("q.wav", b"", "audio/wav")})
    assert resp.status_code == 400


async def test_asr_upstream_error_becomes_502(client, monkeypatch):
    _sarvam_mock(monkeypatch, lambda r: httpx.Response(429, text="quota"))
    resp = await client.post("/v1/asr", files={"file": ("q.wav", FAKE_WAV, "audio/wav")})
    assert resp.status_code == 502


async def test_asr_unconfigured_is_503(monkeypatch):
    monkeypatch.delenv("SARVAM_API_KEY", raising=False)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.post("/v1/asr", files={"file": ("q.wav", FAKE_WAV, "audio/wav")})
    assert resp.status_code == 503


# ── /v1/tts ────────────────────────────────────────────────────────────────

async def test_tts_returns_wav(client, monkeypatch):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["payload"] = json.loads(request.read())
        return httpx.Response(200, json={
            "audios": [base64.b64encode(FAKE_WAV).decode()]})

    _sarvam_mock(monkeypatch, handler)
    resp = await client.post("/v1/tts", json={"text": "यह रहा जवाब", "lang": "hi"})
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "audio/wav"
    assert resp.content == FAKE_WAV
    assert seen["payload"]["target_language_code"] == "hi-IN"
    assert seen["payload"]["model"] == "bulbul:v3"


async def test_tts_caches_repeat_captions(client, monkeypatch):
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(1)
        return httpx.Response(200, json={
            "audios": [base64.b64encode(FAKE_WAV).decode()]})

    _sarvam_mock(monkeypatch, handler)
    for _ in range(3):
        resp = await client.post("/v1/tts", json={"text": "Here's what I found.", "lang": "en"})
        assert resp.content == FAKE_WAV
    assert len(calls) == 1


async def test_tts_upstream_error_becomes_502(client, monkeypatch):
    _sarvam_mock(monkeypatch, lambda r: httpx.Response(500, text="boom"))
    resp = await client.post("/v1/tts", json={"text": "hello", "lang": "en"})
    assert resp.status_code == 502
