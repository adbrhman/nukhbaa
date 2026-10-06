-- ============================================================================
-- Migration 0095: every feature's usage and the signup retention, read from
-- one place (2026-10-06)
--
-- Phase 4 of the world-class plan, "full measurement": every feature has a
-- weekly usage number read from one place, and a weekly report of how many
-- players return 7 and 30 days after signing up.
--
--   * gamification.player_active_days -- a player was active on a Riyadh
--     day when the game recorded an event (0053) or the app reported a
--     screen open (0093) that day.
--   * gamification.feature_use_days -- one row per (player, Riyadh day,
--     feature) used, from the tables each feature writes: predict, double,
--     duel_create, duel_accept, prediction_reaction, group_reaction,
--     group_join, push_open, and screen:<name> for every screen opened.
--   * gamification.kpi_feature_usage_weekly / _monthly -- per period and
--     feature: players, the period's predictors, and the share of them.
--     The feature 'social' is anyone who challenged, accepted, reacted or
--     joined a group: the phase 1 gate reads its monthly share (20%).
--   * gamification.kpi_signup_retention -- per signup week: signups, and of
--     those whose window has closed, how many were active on some day 7 to
--     13 (d7) and 30 to 36 (d30) after signing up.
--
-- Views, not tables, like 0054, 0069 and 0093: computed on read, they never
-- disagree with their sources. Server-only: revoked from anon and
-- authenticated.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

create or replace view gamification.player_active_days as
select a.user_id, a.activity_date
from gamification.user_active_days a
union
select v.user_id, v.view_date
from gamification.screen_views v;

comment on view gamification.player_active_days is
  'Distinct (player, Riyadh day) with a game event (0053) or a screen open '
  '(0093) that day (0095).';

create or replace view gamification.feature_use_days as
select distinct p.user_id,
       (fp.submitted_at at time zone 'Asia/Riyadh')::date as use_date,
       'predict'::text as feature
from prediction.fixture_predictions fp
join competition.participants p on p.id = fp.participant_id
union all
select distinct p.user_id,
       (fp.submitted_at at time zone 'Asia/Riyadh')::date,
       'double'
from prediction.fixture_predictions fp
join competition.participants p on p.id = fp.participant_id
where fp.is_double
union all
select distinct p.user_id,
       (c.created_at at time zone 'Asia/Riyadh')::date,
       'duel_create'
from social.duel_challenges c
join competition.participants p on p.id = c.challenger_participant_id
union all
select distinct p.user_id,
       (d.accepted_at at time zone 'Asia/Riyadh')::date,
       'duel_accept'
from social.duels d
join competition.participants p on p.id = d.opponent_participant_id
union all
select distinct r.user_id,
       (r.reacted_at at time zone 'Asia/Riyadh')::date,
       'prediction_reaction'
from social.prediction_reactions r
union all
select distinct r.user_id,
       (r.reacted_at at time zone 'Asia/Riyadh')::date,
       'group_reaction'
from social.fixture_reactions r
union all
select distinct m.user_id,
       (m.joined_at at time zone 'Asia/Riyadh')::date,
       'group_join'
from "group".group_memberships m
union all
select distinct o.user_id,
       (o.opened_at at time zone 'Asia/Riyadh')::date,
       'push_open'
from notification.push_opens o
union all
select distinct v.user_id, v.view_date, 'screen:' || v.screen
from gamification.screen_views v;

comment on view gamification.feature_use_days is
  'One row per (player, Riyadh day, feature) used, from the tables each '
  'feature writes (0095). Read by kpi_feature_usage_weekly and _monthly.';

create or replace view gamification.kpi_feature_usage_weekly as
with uses as (
  select distinct
    f.use_date - (extract(isodow from f.use_date)::int - 1) as week_start,
    f.feature,
    f.user_id
  from gamification.feature_use_days f
  union
  select distinct
    f.use_date - (extract(isodow from f.use_date)::int - 1),
    'social',
    f.user_id
  from gamification.feature_use_days f
  where f.feature in ('duel_create', 'duel_accept', 'prediction_reaction',
                      'group_reaction', 'group_join')
),
predictors as (
  select u.week_start, count(*) as predictors
  from uses u
  where u.feature = 'predict'
  group by u.week_start
)
select
  u.week_start,
  u.feature,
  count(*) as players,
  coalesce(pr.predictors, 0) as predictors,
  round(count(*)::numeric / nullif(pr.predictors, 0), 4)
    as share_of_predictors
from uses u
left join predictors pr on pr.week_start = u.week_start
group by u.week_start, u.feature, pr.predictors;

comment on view gamification.kpi_feature_usage_weekly is
  'Per Riyadh week (from Monday) and feature: players who used it, the '
  'week''s predictors, and the share of them (0095).';

create or replace view gamification.kpi_feature_usage_monthly as
with uses as (
  select distinct
    date_trunc('month', f.use_date::timestamp)::date as month,
    f.feature,
    f.user_id
  from gamification.feature_use_days f
  union
  select distinct
    date_trunc('month', f.use_date::timestamp)::date,
    'social',
    f.user_id
  from gamification.feature_use_days f
  where f.feature in ('duel_create', 'duel_accept', 'prediction_reaction',
                      'group_reaction', 'group_join')
),
predictors as (
  select u.month, count(*) as predictors
  from uses u
  where u.feature = 'predict'
  group by u.month
)
select
  u.month,
  u.feature,
  count(*) as players,
  coalesce(pr.predictors, 0) as predictors,
  round(count(*)::numeric / nullif(pr.predictors, 0), 4)
    as share_of_predictors
from uses u
left join predictors pr on pr.month = u.month
group by u.month, u.feature, pr.predictors;

comment on view gamification.kpi_feature_usage_monthly is
  'Per Riyadh month and feature: players who used it, the month''s '
  'predictors, and the share of them. The phase 1 gate is the social row '
  '(0095).';

create or replace view gamification.kpi_signup_retention as
with cohort as (
  select
    u.id as user_id,
    (u.created_at at time zone 'Asia/Riyadh')::date as signup_day
  from identity.users u
),
marked as (
  select
    c.signup_day - (extract(isodow from c.signup_day)::int - 1)
      as cohort_week,
    c.signup_day + 13 < (now() at time zone 'Asia/Riyadh')::date as d7_due,
    c.signup_day + 36 < (now() at time zone 'Asia/Riyadh')::date as d30_due,
    exists (
      select 1 from gamification.player_active_days a
      where a.user_id = c.user_id
        and a.activity_date between c.signup_day + 7 and c.signup_day + 13
    ) as d7_back,
    exists (
      select 1 from gamification.player_active_days a
      where a.user_id = c.user_id
        and a.activity_date between c.signup_day + 30 and c.signup_day + 36
    ) as d30_back
  from cohort c
)
select
  m.cohort_week,
  count(*) as signups,
  count(*) filter (where m.d7_due) as d7_due,
  count(*) filter (where m.d7_due and m.d7_back) as d7_returned,
  round(
    (count(*) filter (where m.d7_due and m.d7_back))::numeric
      / nullif(count(*) filter (where m.d7_due), 0),
    4
  ) as d7_rate,
  count(*) filter (where m.d30_due) as d30_due,
  count(*) filter (where m.d30_due and m.d30_back) as d30_returned,
  round(
    (count(*) filter (where m.d30_due and m.d30_back))::numeric
      / nullif(count(*) filter (where m.d30_due), 0),
    4
  ) as d30_rate
from marked m
group by m.cohort_week;

comment on view gamification.kpi_signup_retention is
  'Per signup week (Riyadh, from Monday): signups, and of those whose window '
  'has closed, how many were active on a day 7 to 13 (d7) or 30 to 36 (d30) '
  'after signing up (0095).';

revoke all on
  gamification.player_active_days,
  gamification.feature_use_days,
  gamification.kpi_feature_usage_weekly,
  gamification.kpi_feature_usage_monthly,
  gamification.kpi_signup_retention
from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0095_feature_usage_and_retention')
on conflict (version) do nothing;

commit;
