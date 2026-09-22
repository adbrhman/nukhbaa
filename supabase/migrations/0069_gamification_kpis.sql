-- ============================================================================
-- Migration 0069: the measurement the plan asked for (P2-8, P3-8, P4-6)
--
-- One table -- notification.push_opens, one row per tap on a push (the app
-- reports the push's link, batch 3b) -- and read-only views over what the
-- game already records. Views, not tables: like 0054 and 0062 they are
-- computed on read and can never disagree with their sources.
--
-- Every day and week is a Riyadh day / a Riyadh week opening on Monday.
-- "Active" means at least one gamification event that day (0053), as in
-- 0054's daily_active_users.
--
-- Server-only: RLS on the table, no policy; every view revoked from anon and
-- authenticated, as 0062 did for the earlier ones.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

create table if not exists notification.push_opens (
  id        bigint generated always as identity primary key,
  user_id   uuid        not null
    references identity.users (id) on delete cascade,
  link      text        not null,
  opened_at timestamptz not null default now(),
  constraint push_opens_link_check
    check (link in ('fixtures', 'league', 'inbox'))
);

comment on table notification.push_opens is
  'One row per tap on a push (P3-8), with the push''s link. Written by '
  'POST /me/push-opened only; read by notification.kpi_push_funnel.';

create index if not exists push_opens_user_opened_idx
  on notification.push_opens (user_id, opened_at);

alter table notification.push_opens enable row level security;
revoke all on notification.push_opens from anon, authenticated;

-- Distinct (user, Riyadh day) pairs with any gamification event.
create or replace view gamification.user_active_days as
select distinct
  e.user_id,
  (e.occurred_at at time zone 'Asia/Riyadh')::date as activity_date
from gamification.events e;

-- P2-8: per week, active players and the share active on 3+ days, weekly-
-- league members against everyone else.
create or replace view gamification.kpi_weekly_engagement as
with per_user as (
  select
    (a.activity_date - (extract(isodow from a.activity_date)::int - 1))
      as week_start,
    a.user_id,
    count(*) as active_days
  from gamification.user_active_days a
  group by 1, 2
)
select
  pu.week_start,
  exists (
    select 1
    from gamification.weekly_league_members m
    where m.week_start = pu.week_start
      and m.user_id = pu.user_id
  ) as in_league,
  count(*) as active_users,
  count(*) filter (where pu.active_days >= 3) as active_3plus,
  round(
    (count(*) filter (where pu.active_days >= 3))::numeric
      / nullif(count(*), 0),
    4
  ) as rate_3plus
from per_user pu
group by 1, 2;

-- P2-8: of a week's league members, how many hold a seat the next week.
create or replace view gamification.kpi_league_retention as
select
  m.week_start,
  count(*) as members,
  count(n.user_id) as returned_next_week,
  round(count(n.user_id)::numeric / nullif(count(*), 0), 4) as retention
from gamification.weekly_league_members m
left join gamification.weekly_league_members n
  on n.user_id = m.user_id
 and n.week_start = m.week_start + 7
group by m.week_start;

-- P3-8: per Riyadh day and kind, pushes sent, opened the same day, and
-- followed by activity that day or the next (the "back within 24 hours").
create or replace view notification.kpi_push_funnel as
with sent as (
  select rs.reminder_date as day, 'reminder'::text as kind,
         'fixtures'::text as link, rs.user_id
  from notification.reminder_sends rs
  union all
  select ps.send_date, ps.kind,
         case ps.kind when 'overtaken' then 'league' else 'fixtures' end,
         ps.user_id
  from notification.proactive_sends ps
)
select
  s.day,
  s.kind,
  count(*) as sent,
  count(*) filter (
    where exists (
      select 1
      from notification.push_opens o
      where o.user_id = s.user_id
        and o.link = s.link
        and (o.opened_at at time zone 'Asia/Riyadh')::date = s.day
    )
  ) as opened,
  count(*) filter (
    where exists (
      select 1
      from gamification.user_active_days a
      where a.user_id = s.user_id
        and a.activity_date between s.day and s.day + 1
    )
  ) as returned_24h
from sent s
group by 1, 2;

-- P3-8: of the users with a device, how many switched each push off.
create or replace view notification.kpi_push_opt_outs as
select
  count(*) as users_with_devices,
  count(*) filter (where np.prediction_reminder = false) as reminder_off,
  count(*) filter (where np.pre_match = false) as pre_match_off,
  count(*) filter (where np.streak_saver = false) as streak_saver_off,
  count(*) filter (where np.overtaken = false) as overtaken_off
from (select distinct dt.user_id from notification.device_tokens dt) d
left join notification.notification_preferences np
  on np.user_id = d.user_id;

-- P4-6: by first active day, how many were active again on day 14 and in
-- week 4 (days 21 to 27).
create or replace view gamification.kpi_retention as
with firsts as (
  select a.user_id, min(a.activity_date) as first_day
  from gamification.user_active_days a
  group by a.user_id
)
select
  f.first_day as cohort_day,
  count(*) as users,
  count(*) filter (
    where exists (
      select 1
      from gamification.user_active_days a
      where a.user_id = f.user_id
        and a.activity_date = f.first_day + 14
    )
  ) as d14,
  count(*) filter (
    where exists (
      select 1
      from gamification.user_active_days a
      where a.user_id = f.user_id
        and a.activity_date between f.first_day + 21 and f.first_day + 27
    )
  ) as w4
from firsts f
group by f.first_day;

-- P4-6: every player's accuracy per Riyadh month -- is it rising?
create or replace view gamification.kpi_accuracy_trend as
select
  date_trunc('month', sch.kickoff_at at time zone 'Asia/Riyadh')::date
    as month,
  count(*) as decided,
  count(*) filter (
    where fs.grade in ('exact_scoreline', 'correct_outcome')
  ) as correct,
  round(
    (count(*) filter (
      where fs.grade in ('exact_scoreline', 'correct_outcome')
    ))::numeric / nullif(count(*), 0),
    4
  ) as accuracy
from scoring.fixture_scores fs
join competition.fixture_schedules sch on sch.fixture_id = fs.fixture_id
where fs.grade <> 'pending'
group by 1;

revoke all on
  gamification.user_active_days,
  gamification.kpi_weekly_engagement,
  gamification.kpi_league_retention,
  notification.kpi_push_funnel,
  notification.kpi_push_opt_outs,
  gamification.kpi_retention,
  gamification.kpi_accuracy_trend
from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from notification.push_opens;                        -- 0
-- select * from gamification.kpi_weekly_engagement order by 1 desc limit 4;
-- select * from notification.kpi_push_funnel order by 1 desc limit 8;
-- select * from gamification.kpi_accuracy_trend order by 1 desc;
