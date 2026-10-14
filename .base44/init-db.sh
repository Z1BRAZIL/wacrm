#!/bin/sh
set -e

echo "[init-db] Waiting for GoTrue to have created the auth schema..."
# Poll until auth.uid() exists (created by GoTrue's migration 20211202183645)
until psql -h db -U postgres -d postgres -tAc \
  "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE p.proname='uid' AND n.nspname='auth'" \
  2>/dev/null | grep -q 1; do
  sleep 2
done
echo "[init-db] auth.uid() is available."

echo "[init-db] Running schema init (roles, extensions, storage, publication)..."
psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 -f /init-schema.sql

# Create migration tracking table
psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT NOW()
);
"

# Mark any migrations that were already applied (e.g. by a manual run)
# by checking if the tables/objects they create already exist.
# We do this by inserting all migration filenames that are already recorded.
# If the table is empty but migrations were run manually, we detect this by
# checking if the last migration's table exists.

# Check if migrations were already applied (table exists with data, or
# if the profiles table exists from migration 001 but schema_migrations is empty)
PROFILES_EXISTS=$(psql -h db -U postgres -d postgres -tAc \
  "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='profiles'" 2>/dev/null)
MIGRATIONS_RECORDED=$(psql -h db -U postgres -d postgres -tAc \
  "SELECT count(*) FROM public.schema_migrations" 2>/dev/null)

if [ "$PROFILES_EXISTS" = "1" ] && [ "$MIGRATIONS_RECORDED" = "0" ]; then
  echo "[init-db] Migrations were applied manually — recording all as applied."
  for f in /migrations/*.sql; do
    psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 -c \
      "INSERT INTO public.schema_migrations (filename) VALUES ('$(basename "$f")') ON CONFLICT DO NOTHING"
  done
fi

echo "[init-db] Running app migrations..."
for f in /migrations/*.sql; do
  BASENAME=$(basename "$f")
  APPLIED=$(psql -h db -U postgres -d postgres -tAc \
    "SELECT 1 FROM public.schema_migrations WHERE filename='$BASENAME'" 2>/dev/null)
  if [ "$APPLIED" = "1" ]; then
    echo "[init-db]   $BASENAME (already applied, skipping)"
    continue
  fi
  echo "[init-db]   $BASENAME"
  psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "SET search_path = public, extensions, auth;" -f "$f"
  psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 -c \
    "INSERT INTO public.schema_migrations (filename) VALUES ('$BASENAME')"
done

echo "[init-db] All migrations complete."
