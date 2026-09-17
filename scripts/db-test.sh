#!/usr/bin/env bash
# Apply the migrations to a fresh local database and run the schema tests.
#
# Usage:
#   scripts/db-test.sh                 # uses PGHOST/PGPORT/PGUSER from the environment (defaults: local socket, 5432, current user)
#   PGPORT=54322 PGUSER=postgres scripts/db-test.sh   # e.g. against `supabase start`'s Postgres
#
# The database must be reachable as a superuser. The script creates a scratch
# database "gear_test", adds Supabase-style auth stubs if the auth schema is
# missing (plain Postgres), applies supabase/migrations/*.sql in order, runs
# every file in supabase/tests/, and drops the database again.
set -euo pipefail
cd "$(dirname "$0")/.."

DB=gear_test
P="psql -v ON_ERROR_STOP=1 -q"

$P -d postgres -c "drop database if exists $DB" >/dev/null
$P -d postgres -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT

$P -d "$DB" <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
end $$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '') $$;
create extension if not exists pgcrypto;
SQL

for f in supabase/migrations/*.sql; do
  echo "migrate  $f"
  $P -d "$DB" -f "$f" 2>&1 | grep -v 'already exists, skipping' || true
done
for f in supabase/tests/*.sql; do
  echo "test     $f"
  $P -d "$DB" -o /dev/null -f "$f"
done
echo "ok"
