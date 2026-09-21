-- ============================================================================
-- Migration 0062: the two deferred KPI views (rest of P0-8)
--
-- 0054 created gamification.daily_active_users and deferred
-- challenge_completion_rate and streak_participation until phase 1 had tables
-- to read. It has them now: gamification.settled_day_seasons (0060) freezes
-- which season played on which Riyadh day, and every completed day is a
-- daily_challenge_completed event (0053).
--
-- ADDITIVE ONLY. Two views, no table, no data written. Safe to re-run.
--
-- ## One day, one population
-- Both views read SETTLED days only, so a figure never moves once its day has
-- ended. A user counts for a day when they are an active participant of a
-- season that played on it -- the same rule as the streak calendar
-- (PostgresStreakRepository) -- AND had joined before the day ended. The join
-- filter keeps a September signup from being counted as having missed the
-- days before it existed.
--
-- ## Why streak_participation carries two rates
-- With no freeze and no grace (streak_tally.dart), "holds a streak on day D"
-- is exactly "completed day D", which is challenge_completion_rate again. What
-- the streak adds is continuity, measured two ways from one numerator:
--   participation_rate = streaking / eligible   (reach: who carries a run
--                                                of 2 or more)
--   retention_rate     = streaking / carried    (hold: of those who completed
--                                                their previous match day, who
--                                                completed this one too)
-- "Previous match day" follows the calendar, per user, over the seasons they
-- are in, so the run counted here is the run the app shows.
--
-- ## Completion is matched on the dedupe key
-- The same expression the streak calendar uses, so the view and the app can
-- never disagree on whether a day was completed, and the unique index on
-- dedupe_key answers it.
--
-- ## Server-only, like daily_active_users
-- A view runs with its owner's rights and would bypass the self-only RLS of
-- gamification.events, so every KPI view is revoked from anon and
-- authenticated -- including 0054's, which never was.
-- ============================================================================

begin;

create or replace view gamification.challenge_completion_rate as
with eligible as (
  select distinct sds.day, p.user_id
  from gamification.settled_day_seasons sds
  join competition.participants p
    on p.season_id = sds.season_id
   and p.status = 'active'::competition.participant_status
   and p.joined_at < ((sds.day + 1)::timestamp at time zone 'Asia/Riyadh')
  where sds.fixture_count > 0
)
select
  el.day                                              as challenge_date,
  count(*)                                            as eligible_users,
  count(e.id)                                         as completed_users,
  round(count(e.id)::numeric / nullif(count(*), 0), 4) as completion_rate
from eligible el
left join gamification.events e
  on e.user_id = el.user_id
 and e.event_type = 'daily_challenge_completed'
 and e.dedupe_key =
   'daily_challenge_completed:' || el.user_id::text || ':' ||
   to_char(el.day, 'YYYY-MM-DD')
group by el.day;

comment on view gamification.challenge_completion_rate is
  'Per settled Riyadh day: active participants of the seasons that played it '
  '(joined before the day ended), how many completed the daily challenge, '
  'and the rate. Settled days only, so a day never changes once reported.';

create or replace view gamification.streak_participation as
with match_days as (
  select
    p.user_id,
    sds.day,
    bool_or(
      p.joined_at < ((sds.day + 1)::timestamp at time zone 'Asia/Riyadh')
    ) as eligible
  from gamification.settled_day_seasons sds
  join competition.participants p
    on p.season_id = sds.season_id
   and p.status = 'active'::competition.participant_status
  where sds.fixture_count > 0
  group by p.user_id, sds.day
),
marked as (
  select
    md.user_id,
    md.day,
    md.eligible,
    exists (
      select 1
      from gamification.events e
      where e.user_id = md.user_id
        and e.event_type = 'daily_challenge_completed'
        and e.dedupe_key =
          'daily_challenge_completed:' || md.user_id::text || ':' ||
          to_char(md.day, 'YYYY-MM-DD')
    ) as completed
  from match_days md
),
runs as (
  select
    m.day,
    m.eligible,
    m.completed,
    coalesce(
      lag(m.completed) over (partition by m.user_id order by m.day),
      false
    ) as prev_completed
  from marked m
)
select
  r.day                                                         as streak_date,
  count(*) filter (where r.eligible)                            as eligible_users,
  count(*) filter (where r.eligible and r.completed and r.prev_completed)
                                                                as streaking_users,
  count(*) filter (where r.eligible and r.prev_completed)       as carried_users,
  round(
    (count(*) filter (where r.eligible and r.completed and r.prev_completed))
      ::numeric
    / nullif(count(*) filter (where r.eligible), 0),
    4
  )                                                             as participation_rate,
  round(
    (count(*) filter (where r.eligible and r.completed and r.prev_completed))
      ::numeric
    / nullif(count(*) filter (where r.eligible and r.prev_completed), 0),
    4
  )                                                             as retention_rate
from runs r
group by r.day;

comment on view gamification.streak_participation is
  'Per settled Riyadh day: eligible users, those carrying a streak of 2 or '
  'more (completed this match day and their previous one), those who had '
  'completed their previous match day, and the reach and hold rates. No '
  'freeze, no grace: one missed match day ends a run, as in the app.';

revoke all on gamification.daily_active_users        from anon, authenticated;
revoke all on gamification.challenge_completion_rate from anon, authenticated;
revoke all on gamification.streak_participation      from anon, authenticated;

commit;

-- Verification (read-only):
-- select * from gamification.challenge_completion_rate order by 1 desc limit 7;
-- select * from gamification.streak_participation      order by 1 desc limit 7;
-- -- completed_users of a day equals the challenge events of that day:
-- select count(*) from gamification.events
--  where event_type = 'daily_challenge_completed'
--    and dedupe_key like '%:' || to_char(current_date - 1, 'YYYY-MM-DD');
