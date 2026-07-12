#!/usr/bin/env bash
set -euo pipefail

: "${NAKUL_API:?Set NAKUL_API to the public HTTPS Render API URL}"
: "${SUPABASE_URL:?Set SUPABASE_URL to the Supabase project URL}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY}"
: "${TURNSTILE_SITE_KEY:?Set TURNSTILE_SITE_KEY to the public Cloudflare widget site key}"
: "${TURNSTILE_BASE_URL:?Set TURNSTILE_BASE_URL to the production web origin registered on the widget}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root/app"

flutter pub get
flutter build web --release \
  --dart-define="NAKUL_API=${NAKUL_API}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}" \
  --dart-define="TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY}" \
  --dart-define="TURNSTILE_BASE_URL=${TURNSTILE_BASE_URL}" \
  --dart-define="NAKUL_AUTH_REDIRECT=${NAKUL_AUTH_REDIRECT:-app.nakul://auth-callback/}" \
  --dart-define="NAKUL_SUPPORT_EMAIL=${NAKUL_SUPPORT_EMAIL:-support@nakul.app}"

npx --yes wrangler@4.110.0 pages deploy build/web \
  --project-name nakul \
  --branch main \
  --commit-dirty=true
