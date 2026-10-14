<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Base44 dev environment

## Architecture
Next.js 16 (App Router) + Supabase (Postgres, GoTrue auth, PostgREST).
The sandbox runs a **local self-hosted Supabase** in Docker Compose
(`docker-compose.base44.yml`), not a hosted Supabase project.

Services: `db` (postgres:15) → `gotrue` (auth) → `db-init` (one-shot:
roles, storage schema, app migrations) → `postgrest` (REST API) → `web`
(Next.js dev server on port 3000).

## Single-origin proxy (Base44 preview only)
Supabase Auth and REST are proxied through the Next.js dev server via
`rewrites()` in `next.config.ts` so cookie-based auth stays same-origin.
The server-side Supabase client uses `SUPABASE_URL=http://localhost:3000`
(gated on `BASE44_PREVIEW_MODE === '1'`). The middleware skips auth logic
for `/auth/v1/` and `/rest/v1/` paths to avoid request recursion. All
three changes are no-ops when `BASE44_PREVIEW_MODE` is unset.

## Local Supabase credentials
JWT secret, anon key, service-role key, and DB passwords are generated
local-dev values in `.env.base44-defaults` and `docker-compose.base44.yml`.
`ENCRYPTION_KEY` and `META_APP_SECRET` are development placeholders —
replace via the Base44 secrets dashboard for WhatsApp integration.

## GoTrue
`GOTRUE_MAILER_AUTOCONFIRM=true` — email verification is skipped in dev,
so signup works immediately. GoTrue creates the `auth` schema on first
start; the `db-init` service waits for `auth.uid()` to exist before
running app migrations.

## Migration tracking
`db-init` uses a `public.schema_migrations` table to track which migration
files have been applied. If migrations were applied manually (e.g. during
setup debugging), `db-init` detects this (profiles table exists but
schema_migrations is empty) and marks all as applied, then skips them on
subsequent runs. This avoids re-running non-idempotent migrations (e.g.
migration 017 creates policies without DROP IF EXISTS).

## PostgREST healthcheck
The `postgrest/postgrest` image has no shell, curl, or wget, so no
healthcheck is configured. The `web` service depends on
`service_started` (not `service_healthy`) for postgrest.

## Verification
- `docker compose -f docker-compose.base44.yml up -d --build`
- App at `http://localhost:3000` → redirects to `/login`
- Signup at `/signup` → auto-confirmed → redirected to `/dashboard`
- WhatsApp features (broadcasts, templates, webhooks) need real Meta
  credentials and are not functional with dev placeholders.
