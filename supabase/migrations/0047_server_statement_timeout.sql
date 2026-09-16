-- 0047: bound every statement the API server runs, inside Postgres.
--
-- The server abandons a query after 10 s (Dart-side timeout), but that only
-- stops waiting: the statement keeps running in Postgres and holds one of the
-- pool's 8 connections. A few stuck statements at once exhausted the pool and
-- froze every request. A role-level statement_timeout makes Postgres cancel
-- them itself, which returns the connection to the pool.
--
-- Scope: role `postgres`, the role the server's pooler user
-- (`postgres.<project-ref>`) maps to. Applies to NEW sessions only, so restart
-- the Northflank service once after applying.
--
-- Unaffected: the weekly backup (pg_dump sets statement_timeout = 0 for its
-- own session). A long manual operation in the SQL editor can lift it for its
-- session with `set statement_timeout = 0;`.
--
-- Check:    select rolconfig from pg_roles where rolname = 'postgres';
-- Rollback: alter role postgres reset statement_timeout;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'postgres') then
    execute 'alter role postgres set statement_timeout = ''20s''';
  end if;
end;
$$;
