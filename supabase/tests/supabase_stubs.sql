-- The parts of a Supabase project that the migrations expect and a plain
-- Postgres does not have: the API roles, auth.users and auth.uid(), and the
-- storage tables. Used ONLY by .github/workflows/db-tests.yml to apply every
-- migration to an ephemeral Postgres; never run against the live database.
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema auth;
create table auth.users (
  id                 uuid primary key,
  email              text,
  email_confirmed_at timestamptz,
  created_at         timestamptz default now()
);
create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function auth.role() returns text
language sql stable as $$ select 'service_role'::text $$;

create schema storage;
create table storage.buckets (
  id                 text primary key,
  name               text,
  public             boolean,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  owner              uuid
);
create table storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text,
  name       text,
  owner      uuid,
  metadata   jsonb,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
create function storage.protect_delete() returns trigger
language plpgsql as $$ begin return old; end $$;
create function storage.foldername(name text) returns text[]
language sql as $$ select string_to_array(name, '/') $$;
