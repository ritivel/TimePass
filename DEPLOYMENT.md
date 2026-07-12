# Nakul production deployment

Nakul uses Supabase for identity and user data, Render for the authenticated
Python orchestration API, and Cloudflare Pages for the Flutter web app. The
Flutter Android app uses the same Supabase project and Render API.

## 1. Supabase

1. Link this repository to the intended project:
   `npx supabase link --project-ref <project-ref>`.
2. Review the pending migration with `npx supabase db diff --linked`, then run
   `npx supabase db push`.
3. In Authentication > URL Configuration, set the production web URL as the
   Site URL. Add the production web URL and
   `app.nakul://auth-callback/**` as redirect URLs.
4. Enable email/password, anonymous sign-ins, and manual identity linking.
   Anonymous auth powers the five-question guest trial without a login screen.
   Create an invisible Cloudflare Turnstile widget whose allowed hostname is
   the production web hostname. Build both web and Android with its public site
   key and matching HTTPS origin, then enable that widget's secret under
   Supabase Auth > Bot and Abuse Protection. Do not enable the Supabase CAPTCHA
   toggle before deploying a client build with these values, because Supabase
   will correctly reject unprotected auth requests. To ship Google
   upgrade/login, create Google OAuth web credentials and enable the Google
   provider in Supabase Auth.
5. Configure custom SMTP before public launch so confirmation and recovery
   mail use a branded sender and production delivery limits.
6. Copy the project URL and **publishable key** for client builds. Copy the
   **secret/service-role key** only to Render.

The migration explicitly grants Data API access and enables RLS. Verify in the
SQL editor that an authenticated user can only select, change, and delete rows
whose `user_id` matches `auth.uid()`.

## 2. Render API

Create a Blueprint from `render.yaml`. Render prompts for every secret marked
`sync: false`:

- `NAKUL_ALLOWED_ORIGINS`: exact Cloudflare production origin, with preview
  origins added only when intentionally supported.
- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`.
- `GEMINI_API_KEY`, `SARVAM_API_KEY`, and `DATA_GOV_IN_API_KEY`.

After deployment, verify `https://<render-host>/healthz` returns 200. A request
to `/v1/query` without a Supabase bearer token must return 401. Attach the API
custom domain in Render or proxy it through Cloudflare, then update the web
build's `NAKUL_API` value.

## 3. Cloudflare Pages

Authenticate Wrangler (`npx wrangler login`), export the non-secret public
build values, and run:

```sh
export NAKUL_API=https://api.example.com
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_PUBLISHABLE_KEY=<publishable-key>
export TURNSTILE_SITE_KEY=<public-site-key>
export TURNSTILE_BASE_URL=https://<production-web-hostname>
./scripts/deploy_web.sh
```

Add the production custom domain to the `nakul` Pages project. The build ships
security headers, an SPA fallback, a no-cache service worker shell, and only
public client configuration.

## 4. Android release

Use the owner-held release keystore described in `app/README.md`, then build:

```sh
cd app
flutter build appbundle --release \
  --dart-define=NAKUL_API=https://api.example.com \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> \
  --dart-define=TURNSTILE_SITE_KEY=<public-site-key> \
  --dart-define=TURNSTILE_BASE_URL=https://<production-web-hostname>
```

The release manifest blocks cleartext HTTP. Test email confirmation, Google
redirect, password recovery, cross-device chat sync, deletion, microphone
permission, and account deletion on a signed release before Play submission.

## 5. Required launch checks

- Use separate Supabase and Render projects for staging and production.
- Enable Supabase database backups and Auth abuse protection/CAPTCHA.
- Confirm the three Supabase Cron jobs from the retention migration are active:
  stale anonymous users and their cascading data after 30 days, product events
  after 90 days, and Cron run details after 30 days.
- Put Cloudflare rate limiting and bot rules in front of `/v1/asr`, `/v1/tts`,
  `/v1/visual`, and `/v1/query`; keep `/healthz` public.
- Set spend alerts for Gemini, Sarvam, Render, and Supabase.
- Replace `support@nakul.app` at build time if that mailbox is not active.
- Complete a privacy/legal review for the operating entity and India DPDP
  obligations before inviting public users.
