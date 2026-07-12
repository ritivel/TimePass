# Nakul — visual answer + action engine for Indian daily life

Ask anything (hi/en/te) → get a generated interactive interface, not a wall of chat text.
Production mode opens directly into a five-question guest trial, then upgrades
the same Supabase anonymous user to email or Google so existing chats are kept.
See `PRODUCT_SPEC.md` (what & why) and `COMPONENT_CATALOG.md` (the UI contract).

## Layout

| Path | What |
|---|---|
| `catalog/` | **Source of truth** for the component catalog. `catalog.yaml` → generator → `catalog/dist/catalog.json` (A2UI catalog schema), `catalog/dist/system_prompt.md` (LLM prompt fragment), `app/lib/catalog/schemas.g.dart` (Flutter schemas). |
| `server/` | Thin orchestrator (Python/FastAPI). Keyword fast-path (exact hero matches) or LLM pipeline — which can itself request adapter data (`needsData`) or search grounding (`needsSearch`) — → streams A2UI v0.9.1 messages (NDJSON). Voice: `/v1/asr` + `/v1/tts` (Sarvam). Style-locked answer imagery: `/v1/visual` (Gemini image generation with memory + disk caching). |
| `app/` | Flutter client. Renders A2UI surfaces via `package:genui`; the catalog is the security boundary. |
| `supabase/` | Auth, RLS-protected cloud conversations, write-only product events, the server-owned guest quota, and scheduled privacy retention. |
| `render.yaml` | Render Blueprint for the authenticated production API. |
| `app/wrangler.jsonc` | Cloudflare Pages direct-upload configuration for the web client. |

## Quickstart

```sh
# 1. Generate catalog artifacts (run after any catalog.yaml change)
uv run catalog/generator/generate.py

# 2. Run the server (mock LLM mode works with no keys; fixtures back the hero adapters)
cd server && uv run python -m uvicorn nakul_server.main:app --host 127.0.0.1 --port 8000

# 3. Try a scripted query
curl -sN localhost:8000/v1/query -H 'content-type: application/json' \
  -d '{"query": "ind vs aus score", "lang": "en"}'

# 4. Run the app
cd app && flutter run
```

The no-key quickstart stays device-local. For account sync and the guest trial,
start/link Supabase and pass `SUPABASE_URL` plus
`SUPABASE_PUBLISHABLE_KEY` as Dart defines. Production deployment and release
also require `TURNSTILE_SITE_KEY` and its registered HTTPS
`TURNSTILE_BASE_URL`. Checks are documented in `DEPLOYMENT.md`.

Real integrations are opt-in via env: `GEMINI_API_KEY` (generic tier + generated answer visuals; text falls back to mock),
`SARVAM_API_KEY` (voice; endpoints 503 without it), adapter keys per category (fall back to
fixtures). `GEMINI_IMAGE_MODEL` defaults to `gemini-3.1-flash-image`; generated images are
persisted under `~/.cache/nakul/visuals` (override with `NAKUL_VISUAL_CACHE_DIR`). Secrets come
from SSM (`_ssm_secret`), never committed.

Flutter web localhost origins are allowed automatically. For a hosted web client, set
`NAKUL_ALLOWED_ORIGINS=https://app.example.com` (comma-separated for multiple exact origins);
the server does not ship with wildcard CORS.

To serve a phone over Wi-Fi: run with `--host 0.0.0.0`, then build the installable APK with:

```sh
cd app
flutter build apk --release \
  --dart-define=NAKUL_API=http://<laptop-LAN-IP>:8000
```

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`. The checked-in
release configuration uses the Android debug keystore for private phone testing; a Play Store
upload requires the owner's release keystore and HTTPS-hosted API.

Current same-Wi-Fi phone artifact: `output/android/Nakul-phone-192.168.1.6.apk` (SHA-256
`7b5642f986590470676a6e8987fdd0ee05f3a0bb772e05875474becda22b11bb`). It is configured for
this laptop's current `192.168.1.6:8000`; rebuild if the laptop's LAN address changes.

## Invariants (enforced, not suggested)

- The model can only emit components defined in `catalog/dist/catalog.json`; the server validator
  rejects everything else **before** it ships (fail closed), and the Flutter renderer only maps
  registered `CatalogItem`s.
- Compliance is structural: cricket surfaces require the lag `Notice`, astrology requires the
  disclaimer, monetization components carry non-optional disclosure props (`COMPONENT_CATALOG.md` §5 R6).
- Never edit `catalog/dist/*` or `schemas.g.dart` by hand — change `catalog.yaml` and regenerate.
