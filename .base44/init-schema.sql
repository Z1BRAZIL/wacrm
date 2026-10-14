-- ============================================================
-- Base44 local-dev schema init.
-- Runs AFTER GoTrue has created the auth schema (auth.users etc.)
-- and BEFORE the app's own migrations.
-- Sets up roles, extensions, storage schema, and the realtime
-- publication that the app migrations expect to exist.
-- ============================================================

-- Extensions schema (storage.objects default uses extensions.uuid_generate_v4)
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA extensions;

-- API roles (mirrors what supabase/postgres image creates)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END $$;

-- Authenticator user (PostgREST connects as this user)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE USER authenticator NOINHERIT;
  END IF;
END $$;
ALTER USER authenticator WITH PASSWORD '30674e7374e46a9eadf99ec9c55c1904';
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Grant usage on auth schema so RLS functions (auth.uid) are callable
-- Grant usage on schemas to API roles
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Public schema grants
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ============================================================
-- Storage schema (mirrors supabase/postgres init script)
-- ============================================================
CREATE SCHEMA IF NOT EXISTS storage;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    public boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    CONSTRAINT buckets_owner_fkey FOREIGN KEY (owner) REFERENCES auth.users(id),
    PRIMARY KEY (id)
);
-- Add columns if table already existed without them (idempotent)
ALTER TABLE storage.buckets ADD COLUMN IF NOT EXISTS public boolean DEFAULT false;
ALTER TABLE storage.buckets ADD COLUMN IF NOT EXISTS file_size_limit bigint;
ALTER TABLE storage.buckets ADD COLUMN IF NOT EXISTS allowed_mime_types text[];
CREATE UNIQUE INDEX IF NOT EXISTS bname ON storage.buckets USING BTREE (name);

CREATE TABLE IF NOT EXISTS storage.objects (
    id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    metadata jsonb,
    CONSTRAINT objects_bucketId_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id),
    CONSTRAINT objects_owner_fkey FOREIGN KEY (owner) REFERENCES auth.users(id),
    PRIMARY KEY (id)
);
CREATE UNIQUE INDEX IF NOT EXISTS bucketid_objname ON storage.objects USING BTREE (bucket_id, name);
CREATE INDEX IF NOT EXISTS name_prefix_search ON storage.objects(name text_pattern_ops);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE _parts text[];
BEGIN
    select string_to_array(name, '/') into _parts;
    return _parts[1:array_length(_parts,1)-1];
END
$$;

CREATE OR REPLACE FUNCTION storage.filename(name text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE _parts text[];
BEGIN
    select string_to_array(name, '/') into _parts;
    return _parts[array_length(_parts,1)];
END
$$;

CREATE OR REPLACE FUNCTION storage.extension(name text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE _parts text[]; _filename text;
BEGIN
    select string_to_array(name, '/') into _parts;
    select _parts[array_length(_parts,1)] into _filename;
    return split_part(_filename, '.', 2);
END
$$;

-- Set search_path so app migrations can call uuid_generate_v4() without schema qualification
ALTER DATABASE postgres SET search_path = public, extensions, auth;

-- ============================================================
-- Realtime publication (app migrations ALTER this)
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;
