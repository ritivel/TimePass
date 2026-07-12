from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from nakul_server import visuals
from nakul_server.main import app


client = TestClient(app)


def test_visual_requires_configuration(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    response = client.post(
        "/v1/visual",
        json={
            "prompt": "A clay bowl of lemon rice on a quiet ivory table",
            "aspectRatio": "landscape",
        },
    )
    assert response.status_code == 503


def test_visual_returns_generated_bytes(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test")

    async def fake_generate(prompt: str, aspect: str):
        assert "lemon rice" in prompt
        assert aspect == "square"
        return b"fake-png", "image/png"

    monkeypatch.setattr(visuals, "generate", fake_generate)
    response = client.post(
        "/v1/visual",
        json={
            "prompt": "A clay bowl of lemon rice on a quiet ivory table",
            "aspectRatio": "square",
        },
    )
    assert response.status_code == 200
    assert response.content == b"fake-png"
    assert response.headers["content-type"] == "image/png"


def test_visual_request_is_bounded(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    response = client.post(
        "/v1/visual",
        json={"prompt": "short", "aspectRatio": "landscape"},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_visual_disk_cache_survives_memory_clear(monkeypatch, tmp_path):
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setenv("NAKUL_VISUAL_CACHE_DIR", str(tmp_path))
    calls = 0

    async def fake_generate(prompt: str, aspect: str):
        nonlocal calls
        calls += 1
        return b"persisted-image", "image/jpeg"

    monkeypatch.setattr(visuals, "_generate_uncached", fake_generate)
    visuals.clear_cache()
    first = await visuals.generate("A calm clay study desk at sunrise", "landscape")
    visuals.clear_cache()
    second = await visuals.generate("A calm clay study desk at sunrise", "landscape")

    assert first == second == (b"persisted-image", "image/jpeg")
    assert calls == 1
