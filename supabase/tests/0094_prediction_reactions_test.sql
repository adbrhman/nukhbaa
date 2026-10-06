-- End-to-end test for migration 0094: the statements
-- PostgresPredictionReactionRepository runs (parameters inlined) store one
-- reaction per player per prediction, tell a first reaction from a change,
-- count per prediction with the viewer's own, take a reaction back; the
-- backstop refuses a reaction on one's own prediction, before kickoff, on a
-- missing prediction, or from outside the season; and a prediction_reaction
-- notification can be stored.
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

-- PostgresPredictionReactionRepository.upsertSql
create function pg_temp.react(
  p_id uuid, p_season uuid, p_fixture uuid, p_target uuid, p_user uuid,
  p_emoji text, p_at timestamptz
) returns table (inserted boolean, target_user_id text)
language sql as $$
INSERT INTO social.prediction_reactions
  (id, season_id, fixture_id, target_participant_id, user_id, emoji,
   reacted_at)
VALUES
  (p_id, p_season, p_fixture, p_target, p_user,
   p_emoji::social.reaction_kind, p_at)
ON CONFLICT ON CONSTRAINT prediction_reactions_one_per_player DO UPDATE SET
  emoji = EXCLUDED.emoji,
  reacted_at = EXCLUDED.reacted_at
RETURNING (xmax = 0) AS inserted,
  (SELECT p.user_id::text
     FROM competition.participants p
    WHERE p.id = target_participant_id) AS target_user_id
$$;

-- PostgresPredictionReactionRepository.talliesSql
create function pg_temp.tallies(p_season uuid, p_fixture uuid, p_viewer uuid)
returns table (target_participant_id text, emoji text, reactions int,
               mine boolean)
language sql as $$
SELECT r.target_participant_id::text AS target_participant_id,
       r.emoji::text AS emoji,
       count(*)::int AS reactions,
       bool_or(r.user_id = p_viewer) AS mine
FROM social.prediction_reactions r
WHERE r.season_id = p_season
  AND r.fixture_id = p_fixture
GROUP BY r.target_participant_id, r.emoji
$$;

-- PostgresPredictionReactionRepository.removeSql
create function pg_temp.take_back(p_fixture uuid, p_target uuid, p_user uuid)
returns setof uuid
language sql as $$
DELETE FROM social.prediction_reactions
WHERE fixture_id = p_fixture
  AND target_participant_id = p_target
  AND user_id = p_user
RETURNING id
$$;

do $$
declare
  season uuid := '00000000-0094-4000-8094-000000000001';
  competition uuid := '00000000-0094-4000-8094-000000000002';
  fixture uuid := '00000000-0094-4000-8094-000000000003';
  later uuid := '00000000-0094-4000-8094-000000000004';
  u1 uuid := '00000000-0094-4000-8094-000000000011';
  u2 uuid := '00000000-0094-4000-8094-000000000012';
  u3 uuid := '00000000-0094-4000-8094-000000000013';
  outsider uuid := '00000000-0094-4000-8094-000000000014';
  p1 uuid := '00000000-0094-4000-8094-000000000021';
  p2 uuid := '00000000-0094-4000-8094-000000000022';
  p3 uuid := '00000000-0094-4000-8094-000000000023';
  t0 timestamptz := now();
  r record;
  refused text;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'r1@t.io', now()), (u2, 'r2@t.io', now()), (u3, 'r3@t.io', now()),
    (outsider, 'r4@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 'r1@t.io', 'React One'), (u2, 'r2@t.io', 'React Two'),
    (u3, 'r3@t.io', 'React Three'), (outsider, 'r4@t.io', 'React Four');
  insert into competition.competitions (id, name, format, visibility)
    values (competition, 'React Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, competition, 'React Season',
            t0 - interval '10 days', t0 + interval '20 days');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values (p1, season, u1, t0 - interval '5 days'),
           (p2, season, u2, t0 - interval '5 days'),
           (p3, season, u3, t0 - interval '5 days');
  -- Both fixtures are ahead while the predictions are made.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (fixture, 'Home', 'Away', t0 + interval '1 day'),
           (later, 'Later', 'Side', t0 + interval '2 days');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, fixture, 1), (season, later, 2);
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, submitted_at)
    values ('00000000-0094-4000-8094-000000000031', fixture, p1, 2, 1, t0),
           ('00000000-0094-4000-8094-000000000032', later, p1, 0, 0, t0);
  -- Then the first one kicks off.
  update competition.fixture_schedules
     set kickoff_at = t0 - interval '1 hour'
   where fixture_id = fixture;

  select * into r from pg_temp.react(
    '00000000-0094-4000-8094-000000000041', season, fixture, p1, u2,
    'fire', t0);
  perform pg_temp.check(r.inserted, 'a first reaction is an insert');
  perform pg_temp.check(r.target_user_id = u1::text,
    'the insert names the owner of the prediction');

  select * into r from pg_temp.react(
    '00000000-0094-4000-8094-000000000042', season, fixture, p1, u2,
    'clap', t0 + interval '1 minute');
  perform pg_temp.check(not r.inserted, 'reacting again is a change');
  perform pg_temp.check(
    (select count(*) from social.prediction_reactions
      where fixture_id = fixture) = 1
    and (select emoji::text from social.prediction_reactions
          where fixture_id = fixture) = 'clap',
    'one live reaction per player per prediction, now clap');

  perform pg_temp.react(
    '00000000-0094-4000-8094-000000000043', season, fixture, p1, u3,
    'clap', t0);
  select * into r from pg_temp.tallies(season, fixture, u3)
   where target_participant_id = p1::text and emoji = 'clap';
  perform pg_temp.check(r.reactions = 2 and r.mine,
    'the tally counts both claps and knows the viewer gave one');
  select * into r from pg_temp.tallies(season, fixture, u1)
   where target_participant_id = p1::text and emoji = 'clap';
  perform pg_temp.check(not r.mine, 'the owner gave none of them');

  perform pg_temp.check(
    (select count(*) from pg_temp.take_back(fixture, p1, u3)) = 1,
    'a reaction can be taken back');
  perform pg_temp.check(
    (select count(*) from pg_temp.take_back(fixture, p1, u3)) = 0,
    'taking it back twice removes nothing');

  refused := null;
  begin
    perform pg_temp.react(
      '00000000-0094-4000-8094-000000000044', season, fixture, p1, u1,
      'fire', t0);
  exception when check_violation then
    get stacked diagnostics refused = message_text;
  end;
  perform pg_temp.check(refused = 'social.prediction_reaction_self',
    'nobody reacts to their own prediction');

  refused := null;
  begin
    perform pg_temp.react(
      '00000000-0094-4000-8094-000000000045', season, later, p1, u2,
      'fire', t0);
  exception when check_violation then
    get stacked diagnostics refused = message_text;
  end;
  perform pg_temp.check(refused = 'social.prediction_reaction_before_kickoff',
    'a prediction is not reacted to before its kickoff');

  refused := null;
  begin
    perform pg_temp.react(
      '00000000-0094-4000-8094-000000000046', season, fixture, p2, u1,
      'fire', t0);
  exception when check_violation then
    get stacked diagnostics refused = message_text;
  end;
  perform pg_temp.check(refused = 'social.prediction_reaction_no_prediction',
    'a player without a prediction has nothing to react to');

  refused := null;
  begin
    perform pg_temp.react(
      '00000000-0094-4000-8094-000000000047', season, fixture, p1, outsider,
      'fire', t0);
  exception when check_violation then
    get stacked diagnostics refused = message_text;
  end;
  perform pg_temp.check(
    refused = 'social.prediction_reaction_not_a_participant',
    'only a member of the season reacts');

  insert into notification.notifications
    (id, recipient_id, kind, actor_user_id, fixture_id, subject_ref)
    values ('00000000-0094-4000-8094-000000000051', u1, 'prediction_reaction',
            u2, fixture, 'prediction_reaction:' || fixture || ':' || u2);
  perform pg_temp.check(
    exists (select 1 from notification.notifications
             where kind = 'prediction_reaction' and recipient_id = u1),
    'a prediction_reaction notification is stored');
end $$;

select pg_temp.check(
  not has_table_privilege('authenticated', 'social.prediction_reactions',
                          'select'),
  'the table is server-only');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0094_prediction_reactions'),
  'migration records itself');

rollback;
