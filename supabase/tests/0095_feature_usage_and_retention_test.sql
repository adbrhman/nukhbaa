-- End-to-end test for migration 0095: predictions, a double, a reaction
-- and a screen open show in the weekly and monthly feature usage with the
-- share of predictors (the social row is the phase 1 gate), and the signup
-- retention counts a return in days 7 to 13 and 30 to 36 only once the
-- window has closed.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

do $$
declare
  season uuid := '00000000-0095-4000-8095-000000000001';
  competition uuid := '00000000-0095-4000-8095-000000000002';
  fixture uuid := '00000000-0095-4000-8095-000000000003';
  u1 uuid := '00000000-0095-4000-8095-000000000011';
  u2 uuid := '00000000-0095-4000-8095-000000000012';
  u3 uuid := '00000000-0095-4000-8095-000000000013';
  u4 uuid := '00000000-0095-4000-8095-000000000014';
  p1 uuid := '00000000-0095-4000-8095-000000000021';
  p2 uuid := '00000000-0095-4000-8095-000000000022';
  t0 timestamptz := now();
  -- Two players who signed up the same day, long ago; a third earlier; a
  -- fourth yesterday, whose windows are still open.
  joined timestamptz := now() - interval '400 days';
  today date := (now() at time zone 'Asia/Riyadh')::date;
  signup date := ((now() - interval '400 days') at time zone 'Asia/Riyadh')::date;
  signup3 date := ((now() - interval '500 days') at time zone 'Asia/Riyadh')::date;
  signup4 date := ((now() - interval '1 day') at time zone 'Asia/Riyadh')::date;
  r record;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'k1@t.io', now()), (u2, 'k2@t.io', now()), (u3, 'k3@t.io', now()),
    (u4, 'k4@t.io', now());
  insert into identity.users (id, email, display_name, created_at) values
    (u1, 'k1@t.io', 'Kpi One', joined),
    (u2, 'k2@t.io', 'Kpi Two', joined),
    (u3, 'k3@t.io', 'Kpi Three', now() - interval '500 days'),
    (u4, 'k4@t.io', 'Kpi Four', now() - interval '1 day');
  insert into competition.competitions (id, name, format, visibility)
    values (competition, 'Kpi Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, competition, 'Kpi Season',
            t0 - interval '10 days', t0 + interval '20 days');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values (p1, season, u1, t0 - interval '5 days'),
           (p2, season, u2, t0 - interval '5 days');
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (fixture, 'Home', 'Away', t0 + interval '1 day');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, fixture, 1);
  -- Both predict on Tuesday 4 March 2025, u2 with the double.
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double,
     submitted_at)
    values ('00000000-0095-4000-8095-000000000031', fixture, p1, 1, 0, false,
            '2025-03-04 12:00+03'),
           ('00000000-0095-4000-8095-000000000032', fixture, p2, 2, 2, true,
            '2025-03-04 13:00+03');
  update competition.fixture_schedules
     set kickoff_at = t0 - interval '1 hour'
   where fixture_id = fixture;
  -- u1 reacts to u2's prediction the next day and opens the duels screen.
  insert into social.prediction_reactions
    (id, season_id, fixture_id, target_participant_id, user_id, emoji,
     reacted_at)
    values ('00000000-0095-4000-8095-000000000041', season, fixture, p2, u1,
            'fire', '2025-03-05 20:00+03');
  -- Screen opens: u1 that week; u1 again 8 days after signing up; u3 31
  -- days after; u4 today.
  insert into gamification.screen_views (view_date, screen, user_id, opens)
    values ('2025-03-05', 'duels', u1, 2),
           (signup + 8, 'home', u1, 1),
           (signup3 + 31, 'home', u3, 1),
           (today, 'home', u4, 1);

  select * into r from gamification.kpi_feature_usage_weekly
   where week_start = '2025-03-03' and feature = 'predict';
  perform pg_temp.check(r.players = 2 and r.predictors = 2,
    'two predictors that week');
  select * into r from gamification.kpi_feature_usage_weekly
   where week_start = '2025-03-03' and feature = 'double';
  perform pg_temp.check(r.players = 1 and r.share_of_predictors = 0.5,
    'one of them doubled: half');
  select * into r from gamification.kpi_feature_usage_weekly
   where week_start = '2025-03-03' and feature = 'prediction_reaction';
  perform pg_temp.check(r.players = 1, 'one reacted');
  select * into r from gamification.kpi_feature_usage_weekly
   where week_start = '2025-03-03' and feature = 'screen:duels';
  perform pg_temp.check(r.players = 1, 'a screen open is a feature row');
  select * into r from gamification.kpi_feature_usage_weekly
   where week_start = '2025-03-03' and feature = 'social';
  perform pg_temp.check(r.players = 1 and r.share_of_predictors = 0.5,
    'the social row counts the reactor once: half the predictors');
  select * into r from gamification.kpi_feature_usage_monthly
   where month = '2025-03-01' and feature = 'social';
  perform pg_temp.check(r.players = 1 and r.predictors = 2
                        and r.share_of_predictors = 0.5,
    'the monthly social share is the phase 1 gate');

  select * into r from gamification.kpi_signup_retention
   where cohort_week = signup - (extract(isodow from signup)::int - 1);
  perform pg_temp.check(r.signups = 2 and r.d7_due = 2 and r.d7_returned = 1
                        and r.d7_rate = 0.5,
    'of two signups one came back in days 7 to 13');
  perform pg_temp.check(r.d30_due = 2 and r.d30_returned = 0,
    'neither came back in days 30 to 36');

  select * into r from gamification.kpi_signup_retention
   where cohort_week = signup3 - (extract(isodow from signup3)::int - 1);
  perform pg_temp.check(r.d30_returned = 1, 'a return on day 31 counts');

  select * into r from gamification.kpi_signup_retention
   where cohort_week = signup4 - (extract(isodow from signup4)::int - 1);
  perform pg_temp.check(r.d7_due = 0 and r.d7_rate is null,
    'a signup whose window is open is not counted yet');
end $$;

select pg_temp.check(
  not has_table_privilege('authenticated',
    'gamification.kpi_feature_usage_weekly', 'select'),
  'the views are server-only');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0095_feature_usage_and_retention'),
  'migration records itself');

rollback;
