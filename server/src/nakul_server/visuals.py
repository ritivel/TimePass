"""Generated answer visuals with a server-owned Nakul art direction.

The surface model describes the subject, never the visual system. This module
adds the fixed style, calls Gemini's image model, and keeps memory + disk caches
so restored surfaces and server restarts do not pay for the same image twice.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import tempfile
from collections import OrderedDict
from pathlib import Path

log = logging.getLogger(__name__)

MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-3.1-flash-image")
MAX_CACHE_ITEMS = int(os.environ.get("VISUAL_CACHE_ITEMS", "48"))
MAX_DISK_CACHE_ITEMS = int(os.environ.get("VISUAL_DISK_CACHE_ITEMS", "256"))

_ASPECTS = {
    "landscape": "16:9",
    "square": "1:1",
    "portrait": "4:5",
}

_STYLE = """
Create one premium editorial illustration for a calm Indian mobile assistant.
Art direction: tactile soft-3D objects and miniature scenes, smooth matte clay
and paper materials, gentle natural studio light, quiet ivory or very pale gray
background, subtle realistic shadow, restrained warm marigold with muted teal
and coral only where useful, sophisticated rather than childish. Clean mobile
composition with one clear focal subject and generous negative space. No text,
letters, numbers, logos, brands, UI screenshots, charts, maps, watermarks,
borders, or identifiable real people. Do not visualize unsupported facts.
""".strip()

_cache: OrderedDict[str, tuple[bytes, str]] = OrderedDict()
_inflight: dict[str, asyncio.Task[tuple[bytes, str]]] = {}
_lock = asyncio.Lock()


class VisualError(RuntimeError):
    pass


def available() -> bool:
    return bool(os.environ.get("GEMINI_API_KEY"))


def _key(prompt: str, aspect: str) -> str:
    # Including the art direction prevents old imagery surviving a style
    # change merely because the subject prompt stayed the same.
    payload = f"{MODEL}\n{_STYLE}\n{aspect}\n{prompt.strip()}".encode()
    return hashlib.sha256(payload).hexdigest()


def _cache_dir() -> Path:
    configured = os.environ.get("NAKUL_VISUAL_CACHE_DIR")
    if configured:
        return Path(configured).expanduser()
    root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return root / "nakul" / "visuals"


def _disk_paths(cache_key: str) -> tuple[Path, Path]:
    root = _cache_dir()
    return root / f"{cache_key}.image", root / f"{cache_key}.mime"


def _load_disk(cache_key: str) -> tuple[bytes, str] | None:
    image_path, mime_path = _disk_paths(cache_key)
    try:
        data = image_path.read_bytes()
        mime = mime_path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not data or not mime.startswith("image/"):
        return None
    return data, mime


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        handle.write(data)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def _store_disk(cache_key: str, result: tuple[bytes, str]) -> None:
    image_path, mime_path = _disk_paths(cache_key)
    try:
        _atomic_write(image_path, result[0])
        _atomic_write(mime_path, result[1].encode("utf-8"))
        _prune_disk()
    except OSError as exc:
        # Disk caching is an optimization. A read-only or full filesystem must
        # never turn a successful generated answer into an error.
        log.warning("visual disk cache write failed: %s", exc)


def _prune_disk() -> None:
    root = _cache_dir()
    images = sorted(
        root.glob("*.image"), key=lambda path: path.stat().st_mtime, reverse=True
    )
    for image_path in images[MAX_DISK_CACHE_ITEMS:]:
        mime_path = image_path.with_suffix(".mime")
        image_path.unlink(missing_ok=True)
        mime_path.unlink(missing_ok=True)


async def generate(prompt: str, aspect: str) -> tuple[bytes, str]:
    """Returns ``(image_bytes, mime_type)`` for a validated subject prompt."""
    if not available():
        raise VisualError("image generation is not configured")
    clean = " ".join(prompt.split()).strip()
    if not 8 <= len(clean) <= 500:
        raise VisualError("visual prompt must be 8-500 characters")
    if aspect not in _ASPECTS:
        raise VisualError("unsupported visual aspect ratio")

    cache_key = _key(clean, aspect)
    async with _lock:
        cached = _cache.get(cache_key)
        if cached is not None:
            _cache.move_to_end(cache_key)
            return cached
        task = _inflight.get(cache_key)
        if task is None:
            task = asyncio.create_task(_load_or_generate(clean, aspect, cache_key))
            _inflight[cache_key] = task

    try:
        result = await task
    finally:
        async with _lock:
            _inflight.pop(cache_key, None)

    async with _lock:
        _cache[cache_key] = result
        _cache.move_to_end(cache_key)
        while len(_cache) > MAX_CACHE_ITEMS:
            _cache.popitem(last=False)
    return result


async def _load_or_generate(
    prompt: str, aspect: str, cache_key: str
) -> tuple[bytes, str]:
    cached = await asyncio.to_thread(_load_disk, cache_key)
    if cached is not None:
        return cached
    result = await _generate_uncached(prompt, aspect)
    await asyncio.to_thread(_store_disk, cache_key, result)
    return result


async def _generate_uncached(prompt: str, aspect: str) -> tuple[bytes, str]:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    response = await client.aio.models.generate_content(
        model=MODEL,
        contents=f"{_STYLE}\n\nSubject and composition:\n{prompt}",
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(
                aspect_ratio=_ASPECTS[aspect],
                image_size="512",
            ),
        ),
    )
    for part in response.parts or []:
        inline = getattr(part, "inline_data", None)
        data = getattr(inline, "data", None)
        if data:
            mime = getattr(inline, "mime_type", None) or "image/png"
            return bytes(data), mime
    log.warning("%s returned no image part", MODEL)
    raise VisualError("image model returned no image")


def clear_cache() -> None:
    """Test helper."""
    _cache.clear()
    _inflight.clear()
