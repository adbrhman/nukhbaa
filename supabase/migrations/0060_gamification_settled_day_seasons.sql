-- ============================================================================
-- Migration 0060: settled match days, per season (P1-5 correction)
--
-- 0059 froze one row per Riyadh day for the WHOLE platform, and the streak
-- calendar read it the same way: a day was a "match day" for every user as
-- soon as any season played in it. A participant joins a season explicitly
-- (competition.participants), so a user in one season lost the streak on a
-- day only other seasons played -- a day they could not have played.
--
-- From here a settled day also records WHICH season played in it and with
-- how many fixtures, so the calendar can keep only the seasons the reader
-- actually participates in. gamification.settled_days stays exactly as it
-- is: it remains the "settled through here" watermark, including days with
-- no fixture at all.
--
-- Only days that had fixtures get a row here: the per-season table is not a
-- watermark and has no use for empty days.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

create table if not exists gamification.settled_day_seasons (
  day           date        not null,
  season_id     uuid        not null
                references competition.seasons (id) on delete restrict,
  fixture_count integer     not null,
  settled_at    timestamptz not null default now(),
  primary key (day, season_id),
  constraint settled_day_seasons_fixture_count_positive
    check (fixture_count > 0)
);

comment on table gamification.settled_day_seasons is
  'One row per (Riyadh day that has ended, season that played in it), with '
  'the number of that season fixtures in the day at the moment it was '
  'settled. Frozen and append-only; days with no fixture are not recorded '
  'here -- gamification.settled_days remains the watermark.';

comment on column gamification.settled_day_seasons.fixture_count is
  'Fixtures of this season scheduled in the day when it was settled. A '
  'fixture moved, added or removed later does not change it.';

create index if not exists settled_day_seasons_season_day_idx
  on gamification.settled_day_seasons (season_id, day desc);

create or replace function gamification.reject_settled_day_season_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception
      'gamification.settled_day_seasons is append-only: UPDATE is forbidden'
      using errcode = 'check_violation';
  elsif tg_op = 'DELETE' then
    raise exception
      'gamification.settled_day_seasons is append-only: DELETE is forbidden'
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

comment on function gamification.reject_settled_day_season_mutation() is
  'Append-only backstop: rejects any UPDATE or DELETE on '
  'gamification.settled_day_seasons for every role, including the service '
  'role that bypasses RLS.';

drop trigger if exists settled_day_seasons_reject_mutation
  on gamification.settled_day_seasons;
create trigger settled_day_seasons_reject_mutation
  before update or delete on gamification.settled_day_seasons
  for each row
  execute function gamification.reject_settled_day_season_mutation();

alter table gamification.settled_day_seasons enable row level security;

revoke all on gamification.settled_day_seasons from anon, authenticated;

-- One-time backfill for the days 0059 already settled. Those days were frozen
-- from this same schedule, so reading it once more reproduces them; every day
-- settled after this migration is written by the job itself. ON CONFLICT
-- makes the backfill, and this whole migration, safe to run twice.
insert into gamification.settled_day_seasons (day, season_id, fixture_count)
select (fs.kickoff_at at time zone 'Asia/Riyadh')::date as day,
       sf.season_id,
       count(distinct sf.fixture_id)::int
from competition.season_fixtures sf
join competition.fixture_schedules fs
  on fs.fixture_id = sf.fixture_id
where (fs.kickoff_at at time zone 'Asia/Riyadh')::date
      <= coalesce(
           (select max(sd.day) from gamification.settled_days sd),
           '-infinity'::date
         )
group by 1, 2
on conflict (day, season_id) do nothing;

commit;
