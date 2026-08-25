-- Migration 0021 -- Phase 7.2: CompetitionSeason becomes calendar-driven.
-- Forward-only, expand-only. Safe to re-run.

alter table competition.seasons
  add column if not exists start_at timestamptz,
  add column if not exists end_at timestamptz;

update competition.seasons
set start_at = coalesce(start_at, created_at),
    end_at = coalesce(end_at, created_at + interval '1 day')
where start_at is null or end_at is null;

alter table competition.seasons
  alter column start_at set not null,
  alter column end_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'seasons_window_valid'
      and conrelid = 'competition.seasons'::regclass
  ) then
    alter table competition.seasons
      add constraint seasons_window_valid check (end_at > start_at);
  end if;
end
$$;

comment on column competition.seasons.start_at is
  'UTC instant the season''s calendar window opens (inclusive). Phase 7.2.';
comment on column competition.seasons.end_at is
  'UTC instant the season''s calendar window closes (exclusive).';
