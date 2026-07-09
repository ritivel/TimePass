# TimePass — visual answer + action engine for Indian daily life

Ask anything (hi/en/te) → get a generated interactive interface, not a wall of chat text.
See `PRODUCT_SPEC.md` (what & why) and `COMPONENT_CATALOG.md` (the UI contract).

## Layout

| Path | What |
|---|---|
| `catalog/` | **Source of truth** for the component catalog. `catalog.yaml` → generator → `catalog/dist/catalog.json` (A2UI catalog schema), `catalog/dist/system_prompt.md` (LLM prompt fragment), `app/lib/catalog/schemas.g.dart` (Flutter schemas). |
| `server/` | Thin orchestrator (Python/FastAPI). Keyword fast-path (exact hero matches) or LLM pipeline — which can itself request adapter data (`needsData`) or search grounding (`needsSearch`) — → streams A2UI v0.9.1 messages (NDJSON). Voice: `/v1/asr` + `/v1/tts` (Sarvam). |
| `app/` | Flutter client. Renders A2UI surfaces via `package:genui`; the catalog is the security boundary. |

## Quickstart

```sh
# 1. Generate catalog artifacts (run after any catalog.yaml change)
uv run catalog/generator/generate.py

# 2. Run the server (mock LLM mode works with no keys; fixtures back the hero adapters)
cd server && uv run fastapi dev src/timepass_server/main.py

# 3. Try a scripted query
curl -sN localhost:8000/v1/query -H 'content-type: application/json' \
  -d '{"query": "ind vs aus score", "lang": "en"}'

# 4. Run the app
cd app && flutter run
```

Real integrations are opt-in via env: `GEMINI_API_KEY` (generic tier; falls back to mock),
`SARVAM_API_KEY` (voice; endpoints 503 without it), adapter keys per category (fall back to
fixtures). Secrets come from SSM (`_ssm_secret`), never committed.

To serve a phone over Wi-Fi: run with `--host 0.0.0.0` and build the APK with
`--dart-define=TIMEPASS_API=http://<laptop-LAN-IP>:8000`.

## Invariants (enforced, not suggested)

- The model can only emit components defined in `catalog/dist/catalog.json`; the server validator
  rejects everything else **before** it ships (fail closed), and the Flutter renderer only maps
  registered `CatalogItem`s.
- Compliance is structural: cricket surfaces require the lag `Notice`, astrology requires the
  disclaimer, monetization components carry non-optional disclosure props (`COMPONENT_CATALOG.md` §5 R6).
- Never edit `catalog/dist/*` or `schemas.g.dart` by hand — change `catalog.yaml` and regenerate.
