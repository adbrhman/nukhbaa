-- ============================================================================
-- Migration 0199: the month crowns itself (script 204)
--
-- ADDITIVE ONLY. Two new tables and five read-only functions; no row of any
-- existing table is changed or removed.
--
-- Decided by the owner on 2026-11-02, after the October crowning was made
-- at 00:19 and an Aston Villa - Fulham result was corrected at 01:38, which
-- moved the third place after the podium was set:
--   * the month is crowned by the server, once the last match of the month
--     is over and its result settled, a few minutes later, after every point
--     is scored again;
--   * a match left without a result (postponed or cancelled) does not count,
--     as if it never was, on the last day as on any other;
--   * a tie for first on points, exact scorelines and right outcomes is not
--     decided by the clock: the server waits and the owner crowns;
--   * the prize is the one the admin set ahead for the month, else the
--     previous month's;
--   * admins play and are crowned like everyone else (no change).
--
-- Tables
--   competition.month_prizes        the prize set ahead for a month
--   competition.month_crown_notices what the owner was already told, once
--
-- Functions (server only; read only)
--   competition.month_crown_due(now, window)    the months to look at
--   competition.month_crown_state(season, now, postponed_after)
--   competition.month_crown_rescore(season)     fixtures to score again
--   competition.month_prize_for(season)         the prize to crown with
--   competition.month_results_after(season, since)  latest result write after it
--
-- Apply BEFORE deploying the server. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The prize set ahead for a month. Set and changed by an admin until the
-- month is crowned; the crowning copies it into month_champions.prize, which
-- is frozen there (0078).
-- ---------------------------------------------------------------------------
create table if not exists competition.month_prizes (
  season_id uuid primary key
    constraint month_prizes_season_fkey
      references competition.seasons (id) on delete restrict,
  prize     text not null,
  set_by    uuid not null
    constraint month_prizes_set_by_fkey
      references identity.users (id) on delete restrict,
  set_at    timestamptz not null default now(),
  constraint month_prizes_prize_check
    check (char_length(btrim(prize)) between 1 and 80)
);

comment on table competition.month_prizes is
  'The prize an admin set ahead for a monthly contest (0199). The automatic '
  'crowning takes it, else the previous month''s; refused once the month is '
  'crowned.';

create or replace function competition.month_prizes_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_season uuid := case when tg_op = 'DELETE' then old.season_id
                        else new.season_id end;
begin
  if exists (
    select 1 from competition.month_champions c where c.season_id = v_season
  ) then
    raise exception 'month_prizes: the month is already crowned'
      using errcode = 'check_violation',
            constraint = 'month_prizes_not_crowned';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

drop trigger if exists month_prizes_guard on competition.month_prizes;
create trigger month_prizes_guard
  before insert or update or delete on competition.month_prizes
  for each row execute function competition.month_prizes_guard();

alter table competition.month_prizes enable row level security;
revoke all on competition.month_prizes from anon, authenticated;

-- ---------------------------------------------------------------------------
-- What the owner was told about a month, so a check every two minutes tells
-- him each thing once: the crowning, a tie for first, a month crowned before
-- a later result changed its first three.
-- ---------------------------------------------------------------------------
create table if not exists competition.month_crown_notices (
  season_id uuid not null
    constraint month_crown_notices_season_fkey
      references competition.seasons (id) on delete restrict,
  kind      text not null,
  signature text not null,
  sent_at   timestamptz not null default now(),
  constraint month_crown_notices_pkey primary key (season_id, kind, signature),
  constraint month_crown_notices_kind_check
    check (kind in ('crowned', 'tie', 'changed', 'empty')),
  constraint month_crown_notices_signature_check
    check (char_length(signature) between 1 and 400)
);

comment on table competition.month_crown_notices is
  'One row per thing the owner was told about a month''s automatic '
  'crowning (0199): written once, never changed.';

alter table competition.month_crown_notices enable row level security;
revoke all on competition.month_crown_notices from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The monthly contests that ended within [p_window] before [p_now] and have
-- fixtures: the ones the automatic crowning looks at. A monthly contest is
-- a season labelled MM/YYYY (EnsureUpcomingMonthlySeasons' own rule).
-- crowned_at is null until the month is crowned. A month crowned before
-- this migration was crowned by hand and is left alone.
-- ---------------------------------------------------------------------------
create or replace function competition.month_crown_due(
  p_now timestamptz,
  p_window interval
) returns table (
  season_id  uuid,
  label      text,
  end_at     timestamptz,
  crowned_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select m.id, m.label, m.end_at, m.crowned_at
    from (
      select s.id, s.label, s.end_at,
             (select min(c.crowned_at) from competition.month_champions c
               where c.season_id = s.id) as crowned_at
        from competition.seasons s
       where s.label ~ '^[0-9]{2}/[0-9]{4}$'
         and s.end_at <= p_now
         and s.end_at > p_now - p_window
         and exists (select 1 from competition.season_fixtures sf
                      where sf.season_id = s.id)
    ) m
   where m.crowned_at is null
      or m.crowned_at > coalesce(
           (select am.applied_at from ops.applied_migrations am
             where am.version = '0199_month_auto_crown'),
           'infinity'::timestamptz)
   order by m.end_at, m.id
$$;

-- ---------------------------------------------------------------------------
-- The month's results whose points are not all in (at most 50, oldest
-- kickoff first): scored again, then posted, before the crowning reads the
-- board. The ledger is compared without its streak bonuses, which ride on a
-- fixture but are not its score (PostFixtureToLedger).
-- ---------------------------------------------------------------------------
create or replace function competition.month_crown_rescore(p_season uuid)
returns table (fixture_id uuid)
language sql
stable
set search_path = ''
as $$
  select fs.fixture_id
    from competition.season_fixtures sf
    join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
    join scoring.fixture_results r on r.fixture_id = sf.fixture_id
   where sf.season_id = p_season
     and fs.hidden_at is null
     and not fs.is_test
     and exists (
       select 1
         from prediction.fixture_predictions fp
         left join scoring.fixture_scores sc
           on sc.fixture_id = fp.fixture_id
          and sc.participant_id = fp.participant_id
        where fp.fixture_id = fs.fixture_id
          and (sc.fixture_id is null
               or sc.grade = 'pending'
               or sc.scored_at < r.updated_at
               or coalesce((
                    select sum(e.amount)
                      from ledger.fixture_point_entries e
                     where e.fixture_id = fp.fixture_id
                       and e.participant_id = fp.participant_id
                       and e.entry_kind <> 'streak_bonus'), 0) <> sc.points)
     )
   order by fs.kickoff_at, fs.fixture_id
   limit 50
$$;

-- ---------------------------------------------------------------------------
-- Where a month stands for its crowning, over the fixtures its board sums
-- (shown and not a test, as leaderboard.season_fixture_standings):
--   waiting        no result yet, kicked off inside the month less than
--                  [p_postponed_after] ago: it may still be played or its
--                  result still coming -- the crowning waits for it;
--   skipped        no result, and kicked off after the month or longer ago
--                  than that: postponed or cancelled, it does not count;
--   last_result_at the latest write of any of its results (recorded or
--                  corrected): the crowning waits a few minutes after it;
--   rescore        results whose points are not all in: a prediction with
--                  no score, a pending score, a score older than its result,
--                  or a ledger total that differs from the score.
-- ---------------------------------------------------------------------------
create or replace function competition.month_crown_state(
  p_season uuid,
  p_now timestamptz,
  p_postponed_after interval
) returns table (
  waiting        integer,
  waiting_names  text,
  skipped        integer,
  skipped_names  text,
  last_result_at timestamptz,
  rescore        integer
)
language sql
stable
set search_path = ''
as $$
  with s as (
    select se.id, se.end_at from competition.seasons se where se.id = p_season
  ),
  fx as (
    select fs.fixture_id, fs.kickoff_at,
           fs.home_team || ' × ' || fs.away_team as match,
           r.fixture_id is not null as has_result,
           greatest(r.created_at, r.updated_at) as written_at
      from s
      join competition.season_fixtures sf on sf.season_id = s.id
      join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
      left join scoring.fixture_results r on r.fixture_id = sf.fixture_id
     where fs.hidden_at is null
       and not fs.is_test
  ),
  open_fx as (
    select fx.*,
           (fx.kickoff_at < (select end_at from s)
            and fx.kickoff_at > p_now - p_postponed_after) as is_waiting
      from fx
     where not fx.has_result
  )
  select
    (select count(*)::int from open_fx where is_waiting),
    (select string_agg(match, '، ' order by kickoff_at)
       from (select * from open_fx where is_waiting
              order by kickoff_at limit 10) w),
    (select count(*)::int from open_fx where not is_waiting),
    (select string_agg(match, '، ' order by kickoff_at)
       from (select * from open_fx where not is_waiting
              order by kickoff_at limit 10) k),
    (select max(written_at) from fx),
    (select count(*)::int from competition.month_crown_rescore(p_season))
$$;

-- ---------------------------------------------------------------------------
-- The prize to crown [p_season] with: the one set ahead for it, else the
-- latest earlier month's (its champion's prize first, else the prize set
-- ahead for it); null when there is none.
-- ---------------------------------------------------------------------------
create or replace function competition.month_prize_for(p_season uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select mp.prize from competition.month_prizes mp
      where mp.season_id = p_season),
    (select x.prize
       from (
         select c.prize, s.start_at, 0 as pref
           from competition.month_champions c
           join competition.seasons s on s.id = c.season_id
          where c.prize is not null
         union all
         select mp.prize, s.start_at, 1 as pref
           from competition.month_prizes mp
           join competition.seasons s on s.id = mp.season_id
       ) x
      where x.start_at < (select se.start_at from competition.seasons se
                           where se.id = p_season)
      order by x.start_at desc, x.pref
      limit 1)
  )
$$;

-- ---------------------------------------------------------------------------
-- The latest write of a result of [p_season]'s shown fixtures made after
-- [p_since] (its crowning), or null when there is none. Months crowned
-- before this migration are left alone (null): their crowning was the
-- admin's, by hand.
-- ---------------------------------------------------------------------------
create or replace function competition.month_results_after(
  p_season uuid,
  p_since timestamptz
) returns timestamptz
language sql
stable
set search_path = ''
as $$
  select max(greatest(r.created_at, r.updated_at))
    from competition.season_fixtures sf
    join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
    join scoring.fixture_results r on r.fixture_id = sf.fixture_id
   where sf.season_id = p_season
     and fs.hidden_at is null
     and not fs.is_test
     and greatest(r.created_at, r.updated_at) > p_since
     and p_since > coalesce(
           (select am.applied_at from ops.applied_migrations am
             where am.version = '0199_month_auto_crown'),
           'infinity'::timestamptz)
$$;

revoke all on function competition.month_crown_due(timestamptz, interval)
  from public, anon, authenticated;
revoke all on function competition.month_crown_state(uuid, timestamptz, interval)
  from public, anon, authenticated;
revoke all on function competition.month_crown_rescore(uuid)
  from public, anon, authenticated;
revoke all on function competition.month_prize_for(uuid)
  from public, anon, authenticated;
revoke all on function competition.month_results_after(uuid, timestamptz)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0199_month_auto_crown')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0199_month_auto_crown';                       -- 1 row
-- select * from competition.month_crown_due(now(), interval '3 days');
