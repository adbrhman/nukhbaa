-- End-to-end test for migration 0100: a drawn month, its groups and seats;
-- one seat per player per month and one player per slot; rounds approved in
-- order only; the last round withdrawn while unlocked and never after;
-- append-only everywhere else; the pilot flag. Rolled back at the end.
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

-- The SQLSTATE and constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_state text;
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate,
                          v_constraint = constraint_name;
  return v_state || '/' || coalesce(v_constraint, '');
end $$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1000000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1000000-0000-4000-8000-000000000010', 'c1000000-0000-4000-8000-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1000000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-11-03 15:00Z'),
  ('c1000000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-11-03 18:00Z');

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0100-4000-8100-000000000001', 'h1@t.io', now()),
  ('00000000-0100-4000-8100-000000000002', 'h2@t.io', now()),
  ('00000000-0100-4000-8100-000000000003', 'h3@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0100-4000-8100-000000000001', 'h1@t.io', 'H One'),
  ('00000000-0100-4000-8100-000000000002', 'h2@t.io', 'H Two'),
  ('00000000-0100-4000-8100-000000000003', 'h3@t.io', 'H Three');

do $$
declare
  p1 uuid := '00000000-0100-4000-8100-000000000001';
  p2 uuid := '00000000-0100-4000-8100-000000000002';
  p3 uuid := '00000000-0100-4000-8100-000000000003';
  g1 uuid := '00000000-0100-4000-8100-000000000011';
  g2 uuid := '00000000-0100-4000-8100-000000000012';
  r1 uuid := '00000000-0100-4000-8100-000000000021';
  r2 uuid := '00000000-0100-4000-8100-000000000022';
  r3 uuid := '00000000-0100-4000-8100-000000000023';
  n int;
begin
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_leagues '
      '(id, month_start, division, group_index, capacity) '
      'values (%L, %L, 1, 0, 20)', g1, '2099-11-01')) like '23503/%',
    'a group needs a drawn month');

  insert into gamification.h2h_months (month_start, seated_count)
  values ('2099-11-01', 3);
  insert into gamification.h2h_leagues
    (id, month_start, division, group_index, capacity)
  values (g1, '2099-11-01', 1, 0, 20),
         (g2, '2099-11-01', 4, 0, 4);

  insert into gamification.h2h_league_members
    (league_id, month_start, user_id, slot)
  values (g1, '2099-11-01', p1, 0),
         (g1, '2099-11-01', p2, 1);
  select count(*) into n from gamification.h2h_league_members
   where league_id = g1;
  perform pg_temp.check(n = 2, 'two seats stored in one group');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_league_members '
      '(league_id, month_start, user_id, slot) values (%L, %L, %L, 0)',
      g2, '2099-11-01', p1))
      = '23505/h2h_league_members_month_user_uniq',
    'a player holds one seat per month');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_league_members '
      '(league_id, month_start, user_id, slot) values (%L, %L, %L, 1)',
      g1, '2099-11-01', p3))
      = '23505/h2h_league_members_league_slot_uniq',
    'one player per slot');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_league_members '
      '(league_id, month_start, user_id, slot) values (%L, %L, %L, 4)',
      g2, '2099-11-01', p3))
      = '23514/h2h_league_members_slot_in_capacity',
    'a slot outside the group is refused');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_league_members '
      '(league_id, month_start, user_id, slot) values (%L, %L, %L, 0)',
      g2, '2099-12-01', p3))
      = '23514/h2h_league_members_month_matches_group',
    'a seat filed under another month is refused');

  perform pg_temp.check(
    pg_temp.refusal(
      'insert into gamification.h2h_leagues '
      '(id, month_start, division, group_index, capacity) values '
      '(gen_random_uuid(), ''2099-11-01'', 1, 1, 7)')
      = '23514/h2h_leagues_capacity_even',
    'an odd capacity is refused');

  perform pg_temp.check(
    pg_temp.refusal(
      'insert into gamification.h2h_months (month_start, seated_count) '
      'values (''2099-11-02'', 0)') = '23514/h2h_months_first_day',
    'a month opens on its first day');

  -- Rounds: in order, inside the month, at most 19.
  insert into gamification.h2h_rounds
    (id, month_start, round_no, day, fixture_count)
  values (r1, '2099-11-01', 1, '2099-11-03', 2);

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_rounds '
      '(id, month_start, round_no, day, fixture_count) '
      'values (%L, %L, 3, %L, 6)', r2, '2099-11-01', '2099-11-05'))
      = '23514/h2h_rounds_in_order',
    'a round number cannot be skipped');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_rounds '
      '(id, month_start, round_no, day, fixture_count) '
      'values (%L, %L, 2, %L, 6)', r2, '2099-11-01', '2099-11-02'))
      = '23514/h2h_rounds_in_order',
    'a round cannot come before the last one');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into gamification.h2h_rounds '
      '(id, month_start, round_no, day, fixture_count) '
      'values (%L, %L, 2, %L, 6)', r2, '2099-11-01', '2099-12-01'))
      = '23514/h2h_rounds_day_in_month',
    'a round day lies inside its month');

  insert into gamification.h2h_rounds
    (id, month_start, round_no, day, fixture_count)
  values (r2, '2099-11-01', 2, '2099-11-05', 6),
         (r3, '2099-11-01', 3, '2099-11-07', 9);

  perform pg_temp.check(
    pg_temp.refusal(format(
      'delete from gamification.h2h_rounds where id = %L', r2))
      = '23514/h2h_rounds_withdraw_last',
    'only the last round can be withdrawn');

  delete from gamification.h2h_rounds where id = r3;
  select count(*) into n from gamification.h2h_rounds
   where month_start = '2099-11-01';
  perform pg_temp.check(n = 2, 'the last unlocked round is withdrawn');

  -- Lock round 1 with its fixtures; it can no longer be withdrawn.
  insert into gamification.h2h_round_locks (round_id, fixture_count)
  values (r1, 2);
  insert into gamification.h2h_round_fixtures (round_id, fixture_id)
  values (r1, 'c1000000-0000-4000-8000-0000000000f1'),
         (r1, 'c1000000-0000-4000-8000-0000000000f2');
  delete from gamification.h2h_rounds where id = r2;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'delete from gamification.h2h_rounds where id = %L', r1))
      = '23514/h2h_rounds_withdraw_unlocked',
    'a locked round cannot be withdrawn');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'update gamification.h2h_rounds set day = %L where id = %L',
      '2099-11-04', r1)) like '23514/%',
    'rounds refuse UPDATE');

  perform pg_temp.check(
    pg_temp.refusal('delete from gamification.h2h_round_fixtures')
      like '23514/%',
    'frozen fixtures refuse DELETE');
  perform pg_temp.check(
    pg_temp.refusal('update gamification.h2h_round_locks set fixture_count = 0')
      like '23514/%',
    'locks refuse UPDATE');
  perform pg_temp.check(
    pg_temp.refusal('update gamification.h2h_league_members set slot = 7')
      like '23514/%',
    'seats refuse UPDATE');
  perform pg_temp.check(
    pg_temp.refusal('delete from gamification.h2h_leagues') like '23514/%',
    'groups refuse DELETE');
  perform pg_temp.check(
    pg_temp.refusal('delete from gamification.h2h_months') like '23514/%',
    'months refuse DELETE');

  -- Fill the month to 19 rounds; a 20th is refused.
  for n in 2..19 loop
    insert into gamification.h2h_rounds
      (id, month_start, round_no, day, fixture_count)
    values (gen_random_uuid(), '2099-11-01', n, date '2099-11-03' + n, 6);
  end loop;
  perform pg_temp.check(
    pg_temp.refusal(
      'insert into gamification.h2h_rounds '
      '(id, month_start, round_no, day, fixture_count) '
      'values (gen_random_uuid(), ''2099-11-01'', 20, ''2099-11-29'', 6)')
      = '23514/h2h_rounds_round_no_range',
    'a month holds at most 19 rounds');

  insert into gamification.h2h_month_closures (month_start, member_count)
  values ('2099-11-01', 2);
  perform pg_temp.check(
    pg_temp.refusal(
      'insert into gamification.h2h_month_closures (month_start, member_count) '
      'values (''2099-11-01'', 3)') like '23505/%',
    'a month is closed once');
  perform pg_temp.check(
    pg_temp.refusal('update gamification.h2h_month_closures set member_count = 0')
      like '23514/%',
    'closures refuse UPDATE');

  perform pg_temp.check(
    (select enabled from gamification.feature_flags
      where flag_key = 'h2h_pilot'),
    'the pilot flag exists and is on');

  select count(*) into n from ops.applied_migrations
   where version = '0100_h2h_leagues';
  perform pg_temp.check(n = 1, 'the migration recorded itself');
end $$;

rollback;
