-- End-to-end test of PostgresDuelRecordReader.winsSql (parameter inlined):
-- a duel counts once both scores for its fixture are final, the player
-- with more points won it, a draw is nobody's win, and another season's
-- duels never count. No migration: the query reads 0019 and 0090 tables.
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

-- PostgresDuelRecordReader.winsSql
create function pg_temp.wins(p_season uuid)
returns table (participant_id text, wins int)
language sql as $$
WITH settled AS (
  SELECT d.challenger_participant_id AS a,
         d.opponent_participant_id AS b,
         sa.points AS pa,
         sb.points AS pb
  FROM social.duels d
  JOIN social.duel_challenges c
    ON c.id = d.challenge_id
  JOIN scoring.fixture_scores sa
    ON sa.fixture_id = d.fixture_id
   AND sa.participant_id = d.challenger_participant_id
  JOIN scoring.fixture_scores sb
    ON sb.fixture_id = d.fixture_id
   AND sb.participant_id = d.opponent_participant_id
  WHERE c.season_id = p_season
    AND sa.grade <> 'pending'
    AND sb.grade <> 'pending'
)
SELECT w.participant_id::text AS participant_id, count(*)::int AS wins
FROM (
  SELECT s.a AS participant_id FROM settled s WHERE s.pa > s.pb
  UNION ALL
  SELECT s.b AS participant_id FROM settled s WHERE s.pb > s.pa
) w
GROUP BY w.participant_id
$$;

do $$
declare
  season uuid := '00000000-0097-4000-8097-000000000001';
  other_season uuid := '00000000-0097-4000-8097-000000000005';
  comp uuid := '00000000-0097-4000-8097-000000000002';
  other_comp uuid := '00000000-0097-4000-8097-000000000007';
  f1 uuid := '00000000-0097-4000-8097-000000000003';
  f2 uuid := '00000000-0097-4000-8097-000000000004';
  f3 uuid := '00000000-0097-4000-8097-000000000006';
  u1 uuid := '00000000-0097-4000-8097-000000000011';
  u2 uuid := '00000000-0097-4000-8097-000000000012';
  u3 uuid := '00000000-0097-4000-8097-000000000013';
  p1 uuid := '00000000-0097-4000-8097-000000000021';
  p2 uuid := '00000000-0097-4000-8097-000000000022';
  p3 uuid := '00000000-0097-4000-8097-000000000023';
  q1 uuid := '00000000-0097-4000-8097-000000000031';
  q2 uuid := '00000000-0097-4000-8097-000000000032';
  c1 uuid;
  c2 uuid;
  c3 uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'w1@t.io', now()), (u2, 'w2@t.io', now()), (u3, 'w3@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 'w1@t.io', 'Wins One'), (u2, 'w2@t.io', 'Wins Two'),
    (u3, 'w3@t.io', 'Wins Three');
  insert into competition.competitions (id, name, format, visibility)
    values (comp, 'Wins Test', 'football_scoreline', 'public'),
           (other_comp, 'Other Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, comp, 'Wins Season',
            now() - interval '5 days', now() + interval '20 days'),
           (other_season, other_comp, 'Other Season',
            now() - interval '5 days', now() + interval '20 days');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values (p1, season, u1, now() - interval '4 days'),
           (p2, season, u2, now() - interval '4 days'),
           (p3, season, u3, now() - interval '4 days'),
           (q1, other_season, u1, now() - interval '4 days'),
           (q2, other_season, u2, now() - interval '4 days');
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (f1, 'H1', 'A1', now() + interval '1 day'),
           (f2, 'H2', 'A2', now() + interval '1 day'),
           (f3, 'H3', 'A3', now() + interval '1 day');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, f1, 1), (season, f2, 2), (other_season, f3, 1);
  select social.create_duel_challenge(u1, season, f1, 2, null, now()) into c1;
  select social.create_duel_challenge(u2, season, f2, 1, null, now()) into c2;
  select social.create_duel_challenge(u1, other_season, f3, 1, null, now())
    into c3;
  insert into social.duels
    (challenge_id, fixture_id, challenger_participant_id,
     opponent_participant_id)
    values (c1, f1, p1, p2), (c1, f1, p1, p3), (c2, f2, p2, p3),
           (c3, f3, q1, q2);
  insert into scoring.fixture_scores
    (fixture_id, participant_id, ruleset_version, grade, points) values
    (f1, p1, 1, 'exact_scoreline', 3),
    (f1, p2, 1, 'incorrect', 0),
    (f1, p3, 1, 'exact_scoreline', 3),
    (f2, p2, 1, 'pending', 0),
    (f2, p3, 1, 'correct_outcome', 1),
    (f3, q1, 1, 'exact_scoreline', 6),
    (f3, q2, 1, 'incorrect', 0);

  perform pg_temp.check(
    (select wins from pg_temp.wins(season)
      where participant_id = p1::text) = 1,
    'more points wins the duel');
  perform pg_temp.check(
    not exists (select 1 from pg_temp.wins(season)
                 where participant_id = p3::text),
    'a draw and a pending duel are nobody''s win');
  perform pg_temp.check(
    (select count(*) from pg_temp.wins(season)) = 1,
    'a player who won nothing is absent');
  perform pg_temp.check(
    (select wins from pg_temp.wins(other_season)
      where participant_id = q1::text) = 1,
    'each season counts only its own duels');
end $$;

rollback;
