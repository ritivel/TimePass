FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/app/.venv/bin:$PATH" \
    NAKUL_CATALOG_PATH="/app/catalog/dist/catalog.json" \
    NAKUL_SYSTEM_PROMPT_PATH="/app/catalog/dist/system_prompt.md"

WORKDIR /app

RUN addgroup --system --gid 10001 nakul \
    && adduser --system --uid 10001 --ingroup nakul --home /app nakul

COPY server/pyproject.toml ./
COPY server/uv.lock ./
COPY server/src ./src
COPY catalog/dist /app/catalog/dist

RUN python -m pip install --no-cache-dir uv==0.10.9 \
    && uv sync --frozen --no-dev

USER nakul
EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn nakul_server.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
