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

echo "[init-db] Running app migrations..."
for f in /migrations/*.sql; do
  echo "[init-db]   $(basename "$f")"
  psql -h db -U postgres -d postgres -v ON_ERROR_STOP=1 -f "$f"
done

echo "[init-db] All migrations complete."
