-- End-to-end test for migration 0091: a challenge and a duel on a fixture
-- that exists only where real fixtures exist -- competition.season_fixtures
-- and competition.fixture_schedules -- with no football_data.fixtures row.
-- Before 0091 the create failed with duel_challenges_fixture_id_fkey.
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
  t0 timestamptz := '2030-01-01 12:00+00';
  season uuid := '00000000-0091-4000-8091-000000000001';
  competition uuid := '00000000-0091-4000-8091-000000000002';
  fixture uuid := '00000000-0091-4000-8091-000000000003';
  u1 uuid := '00000000-0091-4000-8091-000000000011';
  u2 uuid := '00000000-0091-4000-8091-000000000012';
  p1 uuid := '00000000-0091-4000-8091-000000000021';
  p2 uuid := '00000000-0091-4000-8091-000000000022';
  c uuid;
  d uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'o1@t.io', now()), (u2, 'o2@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 'o1@t.io', 'Opaque One'), (u2, 'o2@t.io', 'Opaque Two');
  insert into competition.competitions (id, name, format, visibility)
    values (competition, 'Opaque Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, competition, 'Opaque Season',
            '2029-12-01 00:00+00', '2030-02-01 00:00+00');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values (p1, season, u1, t0 - interval '1 day'),
           (p2, season, u2, t0 - interval '1 day');
  -- The fixture exists only as the app's fixtures do.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (fixture, 'Montenegro', 'Armenia', t0 + interval '6 hours');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, fixture, 1);
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
    values
      ('00000000-0091-4000-8091-000000000041', fixture, p1, 0, 2, false, t0),
      ('00000000-0091-4000-8091-000000000042', fixture, p2, 1, 1, false, t0);

  perform pg_temp.check(
    not exists (select 1 from football_data.fixtures where id = fixture),
    'the fixture has no football_data row');

  select social.create_duel_challenge(u1, season, fixture, 1, null, t0) into c;
  perform pg_temp.check(c is not null, 'a challenge is created on the fixture');

  select social.accept_duel_challenge(c, u2, t0 + interval '5 minutes') into d;
  perform pg_temp.check(
    exists (select 1 from social.duels where id = d and fixture_id = fixture),
    'the duel is accepted on the same fixture');
end $$;

select pg_temp.check(
  not exists (
    select 1 from pg_constraint
     where conname in ('duel_challenges_fixture_id_fkey', 'duels_fixture_id_fkey')
  ),
  'no duel table keeps a foreign key to football_data.fixtures');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0091_duels_fixture_opaque'),
  'migration records itself');

rollback;
