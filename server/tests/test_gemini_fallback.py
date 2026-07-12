"""Gemini 5xx recovery: retry the primary model, then fall back to Flash.

503 UNAVAILABLE is Google-side capacity (not rate limiting) and hits
Flash-Lite regardless of billing tier; Flash sits in a separate capacity
pool, so the provider ladders MODEL → MODEL (backoff) → FALLBACK_MODEL.
"""

from types import SimpleNamespace

from google.genai import errors as genai_errors

from nakul_server.llm.base import Chunk, Final
from nakul_server.llm.gemini import FALLBACK_MODEL, MODEL, GeminiProvider


def _server_error() -> genai_errors.ServerError:
    return genai_errors.ServerError(
        503, {"error": {"message": "The model is overloaded.", "status": "UNAVAILABLE"}}
    )


class _FakeClient:
    """Fails configured models with a 503; answers on everything else."""

    def __init__(self, fail_models: set[str], text: str = '{"caption": "ok"}'):
        self.calls: list[str] = []
        self._fail = fail_models
        self._text = text
        self.aio = SimpleNamespace(
            models=SimpleNamespace(
                generate_content_stream=self._stream,
                generate_content=self._complete,
            )
        )

    async def _stream(self, *, model, contents, config):
        self.calls.append(model)
        if model in self._fail:
            raise _server_error()

        async def gen():
            yield SimpleNamespace(text=self._text, candidates=None)

        return gen()

    async def _complete(self, *, model, contents, config):
        self.calls.append(model)
        if model in self._fail:
            raise _server_error()
        return SimpleNamespace(text=self._text, candidates=None)


def _provider(client: _FakeClient) -> GeminiProvider:
    provider = GeminiProvider()
    provider._client = lambda: client  # bypass key/network
    return provider


async def _drain(provider, **kwargs):
    events = []
    async for event in provider.stream("system", [], **kwargs):
        events.append(event)
    return events


async def test_stream_falls_back_to_flash_on_persistent_503():
    client = _FakeClient(fail_models={MODEL})
    events = await _drain(_provider(client))
    # primary tried twice (retry ladder), then the fallback pool answered
    assert client.calls == [MODEL, MODEL, FALLBACK_MODEL]
    assert isinstance(events[-1], Final)
    assert events[-1].text == '{"caption": "ok"}'
    assert any(isinstance(e, Chunk) for e in events)


async def test_stream_no_fallback_when_primary_healthy():
    client = _FakeClient(fail_models=set())
    events = await _drain(_provider(client))
    assert client.calls == [MODEL]
    assert isinstance(events[-1], Final)


async def test_complete_falls_back_to_flash_on_persistent_503():
    client = _FakeClient(fail_models={MODEL})
    final = await _provider(client).complete("system", [])
    assert client.calls == [MODEL, MODEL, FALLBACK_MODEL]
    assert final.text == '{"caption": "ok"}'


async def test_all_models_down_raises():
    import pytest

    client = _FakeClient(fail_models={MODEL, FALLBACK_MODEL})
    with pytest.raises(genai_errors.ServerError):
        await _drain(_provider(client))
    assert client.calls == [MODEL, MODEL, FALLBACK_MODEL]
