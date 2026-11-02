-- ============================================================================
-- Migration 0194: the cache epoch (script 196, review L-11)
--
-- ADDITIVE ONLY. One table with one row, two functions, one statement
-- trigger on each table the server holds in memory. No existing row is
-- written, changed or removed.
--
-- Why: since script 192 the server holds most reads for up to 6 hours and
-- drops them when it writes itself. An edit made in the SQL Editor (a
-- kickoff, a name, a result) is not a write of the server, so it could stay
-- unseen for hours. Any statement on those tables from a session that is
-- not the server's (application_name 'nukhbaa-server') moves the epoch; the
-- server reads it every minute and drops its caches when it moved.
--
-- Statement level: one update of one row per statement, whatever the rows
-- touched. Apply BEFORE pushing the server that reads it. Safe to re-run.
-- ============================================================================

begin;

create table if not exists ops.cache_epoch (
  id         smallint    primary key default 1 check (id = 1),
  epoch      bigint      not null default 0,
  changed_at timestamptz not null default now(),
  source     text
);

insert into ops.cache_epoch (id) values (1) on conflict (id) do nothing;

revoke all on ops.cache_epoch from public;

comment on table ops.cache_epoch is
  'One row: moved by any write made outside the server to a table the '
  'server holds in memory (0194); the server drops its caches when it moves.';

create or replace function ops.bump_cache_epoch(p_source text)
returns void
language sql
set search_path = ''
as $$
  update ops.cache_epoch
     set epoch = epoch + 1,
         changed_at = now(),
         source = left(p_source, 200)
   where id = 1;
$$;

create or replace function ops.cache_epoch_on_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_app text := coalesce(current_setting('application_name', true), '');
begin
  if v_app <> 'nukhbaa-server' then
    perform ops.bump_cache_epoch(
      tg_table_schema || '.' || tg_table_name || ' by '
        || coalesce(nullif(v_app, ''), current_user)
    );
  end if;
  return null;
end
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'competition.fixture_schedules',
    'competition.season_fixtures',
    'competition.participants',
    'competition.seasons',
    'prediction.fixture_predictions',
    'scoring.fixture_results',
    'scoring.fixture_scores',
    'identity.users',
    'football_data.teams',
    'football_data.leagues'
  ] loop
    execute format('drop trigger if exists cache_epoch_on_write on %s', t);
    execute format(
      'create trigger cache_epoch_on_write '
      'after insert or update or delete or truncate on %s '
      'for each statement execute function ops.cache_epoch_on_write()',
      t
    );
  end loop;
end
$$;

insert into ops.applied_migrations (version)
values ('0194_cache_epoch')
on conflict (version) do nothing;

commit;
