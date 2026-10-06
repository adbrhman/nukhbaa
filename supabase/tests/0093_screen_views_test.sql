-- End-to-end test for migration 0093: the statement PostgresScreenViewRepository
-- runs adds a report's opens to the day's row per screen, a second report on
-- the same day sums into the same row, a malformed screen or count is
-- refused, and the weekly view counts players and their share of the week's
-- active players.
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

-- The adapter's statement (PostgresScreenViewRepository.upsertSql) with its
-- parameters inlined.
create function pg_temp.report(
  p_day date, p_user uuid, p_screens text[], p_opens int[], p_now timestamptz
) returns void
language sql as $$
INSERT INTO gamification.screen_views
  (view_date, screen, user_id, opens, first_at, last_at)
SELECT p_day, s.screen, p_user, s.opens, p_now, p_now
FROM unnest(p_screens, p_opens) AS s(screen, opens)
ON CONFLICT (view_date, screen, user_id) DO UPDATE SET
  opens = LEAST(gamification.screen_views.opens + EXCLUDED.opens, 100000),
  last_at = EXCLUDED.last_at
$$;

do $$
declare
  u1 uuid := '00000000-0093-4000-8093-000000000011';
  u2 uuid := '00000000-0093-4000-8093-000000000012';
  u3 uuid := '00000000-0093-4000-8093-000000000013';
  monday date := '2030-01-07';
  t0 timestamptz := '2030-01-07 09:00+00';
  refused boolean;
  r record;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 's1@t.io', now()), (u2, 's2@t.io', now()), (u3, 's3@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 's1@t.io', 'Screen One'), (u2, 's2@t.io', 'Screen Two'),
    (u3, 's3@t.io', 'Screen Three');

  perform pg_temp.report(monday, u1, array['home', 'duels'], array[3, 1], t0);
  perform pg_temp.check(
    (select opens from gamification.screen_views
      where view_date = monday and screen = 'home' and user_id = u1) = 3,
    'a report stores the opens of each screen');

  perform pg_temp.report(
    monday, u1, array['duels'], array[2], t0 + interval '2 hours');
  select opens, first_at, last_at into r from gamification.screen_views
   where view_date = monday and screen = 'duels' and user_id = u1;
  perform pg_temp.check(r.opens = 3,
    'a second report the same day sums into the same row');
  perform pg_temp.check(r.first_at = t0 and r.last_at = t0 + interval '2 hours',
    'first_at stays and last_at moves');
  perform pg_temp.check(
    (select count(*) from gamification.screen_views where user_id = u1) = 2,
    'one row per screen per day, never one per tap');

  perform pg_temp.report(monday + 1, u1, array['duels'], array[1], t0);
  perform pg_temp.check(
    (select count(*) from gamification.screen_views
      where user_id = u1 and screen = 'duels') = 2,
    'the next Riyadh day starts a new row');

  perform pg_temp.report(monday, u1, array['home'], array[99999], t0);
  perform pg_temp.check(
    (select opens from gamification.screen_views
      where view_date = monday and screen = 'home' and user_id = u1) = 100000,
    'a sum is capped at the column limit instead of failing the report');

  refused := false;
  begin
    perform pg_temp.report(monday, u2, array['Home Screen'], array[1], t0);
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'a malformed screen name is refused');

  refused := false;
  begin
    perform pg_temp.report(monday, u2, array['home'], array[0], t0);
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'a count below one is refused');

  -- Three active players that week; two opened duels, one opened home only.
  perform pg_temp.report(monday + 2, u2, array['duels'], array[4], t0);
  insert into gamification.events
    (id, user_id, event_type, dedupe_key, occurred_at) values
    ('00000000-0093-4000-8093-000000000101', u1, 'prediction_placed',
     'test0093:1', t0),
    ('00000000-0093-4000-8093-000000000102', u2, 'prediction_placed',
     'test0093:2', t0),
    ('00000000-0093-4000-8093-000000000103', u3, 'prediction_placed',
     'test0093:3', t0);

  select * into r from gamification.kpi_screen_usage_weekly
   where week_start = monday and screen = 'duels';
  perform pg_temp.check(r.players = 2, 'the week counts each player once');
  perform pg_temp.check(r.opens = 8, 'the week sums the opens');
  perform pg_temp.check(r.active_players = 3,
    'the active players come from user_active_days');
  perform pg_temp.check(r.share_of_active = 0.6667,
    'the share is players over active players');
end $$;

select pg_temp.check(
  not has_table_privilege('authenticated', 'gamification.screen_views',
                          'select'),
  'the table is server-only');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0093_screen_views'),
  'migration records itself');

rollback;
