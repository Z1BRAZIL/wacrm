-- Pre-create schemas and the GoTrue auth-admin user.
-- GoTrue's 00_init_auth_schema creates tables in the "auth" schema but
-- does not CREATE SCHEMA — it relies on the schema already existing.
-- GoTrue also creates types without schema qualification (e.g. factor_type),
-- so the connecting user must have search_path=auth.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA extensions;

CREATE USER supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
ALTER USER supabase_auth_admin WITH PASSWORD '30674e7374e46a9eadf99ec9c55c1904';
ALTER USER supabase_auth_admin SET search_path = "auth";
GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin;
