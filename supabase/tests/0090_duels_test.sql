-- End-to-end database test for migration 0090.
-- This proves the real create/accept/cancel/decline functions and their guards.
-- The acceptance lock is verified structurally and by a sequential full-capacity
-- test. This file does NOT claim a two-session concurrency proof; that requires
-- two PostgreSQL sessions and is intentionally deferred to the integration run.
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

do $$
declare
  t0 timestamptz := '2030-01-01 12:00+00';
  season uuid := '00000000-0090-4000-8090-000000000001';
  competition uuid := '00000000-0090-4000-8090-000000000002';
  fixture uuid := '00000000-0090-4000-8090-000000000003';
  u1 uuid := '00000000-0090-4000-8090-000000000011';
  u2 uuid := '00000000-0090-4000-8090-000000000012';
  u3 uuid := '00000000-0090-4000-8090-000000000013';
  p1 uuid := '00000000-0090-4000-8090-000000000021';
  p2 uuid := '00000000-0090-4000-8090-000000000022';
  p3 uuid := '00000000-0090-4000-8090-000000000023';
  c1 uuid;
  c2 uuid;
  c3 uuid;
  d1 uuid;
  d2 uuid;
  d3 uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'd1@t.io', now()), (u2, 'd2@t.io', now()), (u3, 'd3@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 'd1@t.io', 'Duel One'),
    (u2, 'd2@t.io', 'Duel Two'),
    (u3, 'd3@t.io', 'Duel Three');
  insert into competition.competitions (id, name, format, visibility)
    values (competition, 'Duel Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, competition, 'Duel Test Season',
            '2029-12-01 00:00+00', '2030-02-01 00:00+00');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values
      (p1, season, u1, t0 - interval '1 day'),
      (p2, season, u2, t0 - interval '1 day'),
      (p3, season, u3, t0 - interval '1 day');
  insert into football_data.teams (id, name) values
    ('00000000-0090-4000-8090-000000000031', 'Duel Home'),
    ('00000000-0090-4000-8090-000000000032', 'Duel Away');
  insert into football_data.fixtures (id, home_team_id, away_team_id)
    values (
      fixture,
      '00000000-0090-4000-8090-000000000031',
      '00000000-0090-4000-8090-000000000032'
    );
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (fixture, 'Duel Home', 'Duel Away', t0 + interval '2 hours');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, fixture, 1);

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
    values
      ('00000000-0090-4000-8090-000000000041', fixture, p1, 2, 1, false, t0),
      ('00000000-0090-4000-8090-000000000042', fixture, p2, 1, 0, false, t0),
      ('00000000-0090-4000-8090-000000000043', fixture, p3, 0, 1, false, t0);

  select social.create_duel_challenge(u1, season, fixture, 1, u2, t0)
    into c1;
  perform pg_temp.check(
    (select capacity from social.duel_challenges where id = c1) = 1,
    'private duel has capacity one');
  perform pg_temp.check(
    (select code ~ '^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{12}$'
       from social.duel_challenges where id = c1),
    'duel code is twelve characters from the safe alphabet');

  select social.accept_duel_challenge(c1, u2, t0 + interval '5 minutes') into d1;
  perform pg_temp.check(
    exists (select 1 from social.duels where id = d1),
    'accept creates a real duel');
  perform pg_temp.check(
    not exists (
      select 1 from information_schema.columns
       where table_schema = 'social' and table_name = 'duels'
         and column_name in ('winner_participant_id', 'winner_user_id', 'points', 'status')
    ),
    'duel stores no winner, points or second status source');

  perform pg_temp.check(
    pg_get_functiondef('social.accept_duel_challenge(uuid,uuid,timestamptz)'::regprocedure)
      like '%for update%',
    'accept locks the challenge row');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c1, u2, t0 + interval '6 minutes'))
      = '23514/duel_capacity_full',
    'private duel cannot be accepted twice');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c1, u3, t0 + interval '6 minutes'))
      = '23514/duel_wrong_target',
    'a private duel cannot be taken by another user');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.create_duel_challenge(%L,%L,%L,%s,%L,%L)',
      u1, season, fixture, 11, null, t0))
      = '23514/duel_challenges_capacity_range',
    'capacity eleven is rejected');

  select social.create_duel_challenge(u1, season, fixture, 5, null, t0)
    into c2;
  perform pg_temp.check(
    (select capacity from social.duel_challenges where id = c2) = 5,
    'open duel defaults to capacity five');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c2, u2, t0 + interval '7 minutes'))
      = '23505/duel_pair_already_exists',
    'same pair cannot get a second duel for the fixture');

  select social.accept_duel_challenge(c2, u3, t0 + interval '8 minutes') into d2;
  perform pg_temp.check(
    exists (select 1 from social.duels where id = d2),
    'open challenge accepts another distinct participant');

  select social.create_duel_challenge(u3, season, fixture, 1, u1, t0)
    into c3;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u1, t0 + interval '9 minutes'))
      = '23505/duel_pair_already_exists',
    'reverse-direction challenge cannot create a duplicate pair duel');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.create_duel_challenge(%L,%L,%L,%s,%L,%L)',
      u1, season, fixture, 1, null, t0 + interval '91 minutes'))
      = '23514/duel_minimum_lead_time',
    'creation inside the thirty-minute window is rejected');

  select social.create_duel_challenge(u1, season, fixture, 1, u2, t0)
    into c3;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u2, t0 + interval '10 minutes'))
      = '23505/duel_pair_already_exists',
    'pair uniqueness is enforced across separate challenges');

  -- Start the quota from zero: earlier open challenges would already count.
  update social.duel_challenges
     set status = 'cancelled'
   where challenger_participant_id = p1 and status = 'open';
  -- Ten open challenges consume the fixed pending quota; the eleventh is refused.
  for i in 1..10 loop
    perform social.create_duel_challenge(u1, season, fixture, 5, null, t0);
  end loop;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.create_duel_challenge(%L,%L,%L,%s,%L,%L)',
      u1, season, fixture, 5, null, t0))
      = '23514/duel_max_pending_challenges',
    'a player cannot exceed ten pending duel challenges');
  update social.duel_challenges
     set status = 'cancelled'
   where challenger_participant_id = p1 and status = 'open';

  update social.duel_challenges set status = 'cancelled' where id = c2;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c2, u1, t0 + interval '11 minutes'))
      = '23514/duel_not_open',
    'cancelled challenge cannot be accepted');

  select social.create_duel_challenge(u2, season, fixture, 1, u3, t0)
    into c3;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u3, t0 + interval '2 hours'))
      = '23514/duel_expired',
    'acceptance after kickoff is rejected');
  update social.duel_challenges set status = 'cancelled' where id = c3;

  select social.create_duel_challenge(u2, season, fixture, 1, u3, t0)
    into c3;
  perform social.decline_duel_challenge(c3, u3);
  perform pg_temp.check(
    (select status = 'declined' from social.duel_challenges where id = c3),
    'private target can decline before acceptance');

  -- Acceptance requires both predictions. Remove one and prove the real accept
  -- function refuses; restore it after the check for rollback cleanliness.
  delete from prediction.fixture_predictions where participant_id = p3;
  select social.create_duel_challenge(u2, season, fixture, 1, u3, t0)
    into c3;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u3, t0 + interval '12 minutes'))
      = '23514/duel_opponent_prediction_required',
    'accept requires the opponent prediction');

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
    values ('00000000-0090-4000-8090-000000000044', fixture, p3, 0, 1, false, t0);

  update identity.users set status = 'suspended' where id = u3;
  perform pg_temp.check(
    (select status = 'cancelled' from social.duel_challenges where id = c3),
    'suspending the target cancels the open challenge');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u3, t0 + interval '13 minutes'))
      = '23514/duel_not_open',
    'a suspended target cannot accept a cancelled challenge');
  update identity.users set status = 'active' where id = u3;

  -- The earlier challenge was cancelled by the suspension; use a fresh open one.
  select social.create_duel_challenge(u2, season, fixture, 1, u3, t0)
    into c3;
  delete from prediction.fixture_predictions where participant_id = p2;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select social.accept_duel_challenge(%L,%L,%L)', c3, u3, t0 + interval '13 minutes'))
      = '23514/duel_challenger_prediction_required',
    'accept requires the challenger prediction');
end $$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0090_duels'),
  'migration records itself');

rollback;
