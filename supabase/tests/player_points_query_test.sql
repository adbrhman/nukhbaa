-- Test for PostgresPlayerPointsReader.pointsSql (batch 146b, audit C-01):
-- a player's movements in one month come from the fixture ledger with each
-- match's sides; a player who played but moved nothing is one row without
-- an entry; another month or another player is not read. Keep the body
-- identical to the adapter's constant. Rolled back at the end.
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

-- PostgresPlayerPointsReader.pointsSql
create function pg_temp.points(p_user_id text, p_season_id text)
returns table (participant_id text, id text, fixture_id text, home_team text,
               away_team text, kind text, amount integer,
               occurred_at timestamptz)
language sql as $q$
SELECT p.id::text AS participant_id,
       e.id::text AS id,
       e.fixture_id::text AS fixture_id,
       s.home_team AS home_team,
       s.away_team AS away_team,
       e.entry_kind::text AS kind,
       e.amount AS amount,
       e.occurred_at AS occurred_at
FROM competition.participants p
LEFT JOIN ledger.fixture_point_entries e ON e.participant_id = p.id
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = e.fixture_id
WHERE p.user_id = p_user_id::uuid
  AND p.season_id = p_season_id::uuid
ORDER BY e.occurred_at, e.id
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-146b-4000-8000-000000000001', 'p1@t.io', now()),
  ('00000000-146b-4000-8000-000000000002', 'p2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-146b-4000-8000-000000000001', 'p1@t.io', 'One'),
  ('00000000-146b-4000-8000-000000000002', 'p2@t.io', 'Two');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-146b-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('00000000-146b-4000-8000-0000000000a1', '00000000-146b-4000-8000-0000000000c1', '10/2026', '2026-09-30 21:00+00', '2026-10-31 21:00+00'),
  ('00000000-146b-4000-8000-0000000000a2', '00000000-146b-4000-8000-0000000000c1', '11/2026', '2026-10-31 21:00+00', '2026-11-30 21:00+00');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('00000000-146b-4000-8000-0000000000f1', 'Arsenal', 'Chelsea', '2026-10-10 18:00+00'),
  ('00000000-146b-4000-8000-0000000000f2', 'Liverpool', 'Everton', '2026-10-11 18:00+00');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-146b-4000-8000-0000000000b1', '00000000-146b-4000-8000-0000000000a1', '00000000-146b-4000-8000-000000000001', '2026-10-01'),
  ('00000000-146b-4000-8000-0000000000b2', '00000000-146b-4000-8000-0000000000a2', '00000000-146b-4000-8000-000000000001', '2026-11-01'),
  ('00000000-146b-4000-8000-0000000000b3', '00000000-146b-4000-8000-0000000000a1', '00000000-146b-4000-8000-000000000002', '2026-10-01');
insert into ledger.fixture_point_entries
  (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at) values
  ('00000000-146b-4000-8000-0000000000e2', '00000000-146b-4000-8000-0000000000b1', '00000000-146b-4000-8000-0000000000f2', 'fixture_score', 1, 'fixture_score:f2:b1', '2026-10-11 21:00+00'),
  ('00000000-146b-4000-8000-0000000000e1', '00000000-146b-4000-8000-0000000000b1', '00000000-146b-4000-8000-0000000000f1', 'fixture_score', 3, 'fixture_score:f1:b1', '2026-10-10 21:00+00'),
  ('00000000-146b-4000-8000-0000000000e3', '00000000-146b-4000-8000-0000000000b3', '00000000-146b-4000-8000-0000000000f1', 'fixture_score', 5, 'fixture_score:f1:b3', '2026-10-10 21:00+00');

do $$
begin
  perform pg_temp.check(
    (select count(*) from pg_temp.points('00000000-146b-4000-8000-000000000001', '00000000-146b-4000-8000-0000000000a1')) = 2,
    'the player''s two movements in the month');
  perform pg_temp.check(
    (select string_agg(home_team || ' x ' || away_team || ' ' || amount, ', ' order by occurred_at)
       from pg_temp.points('00000000-146b-4000-8000-000000000001', '00000000-146b-4000-8000-0000000000a1'))
      = 'Arsenal x Chelsea 3, Liverpool x Everton 1',
    'oldest first, with each match''s sides');
  perform pg_temp.check(
    (select bool_and(participant_id = '00000000-146b-4000-8000-0000000000b1' and kind = 'fixture_score')
       from pg_temp.points('00000000-146b-4000-8000-000000000001', '00000000-146b-4000-8000-0000000000a1')),
    'his participation and the entry kind');
  perform pg_temp.check(
    (select count(*) = 1 and bool_and(id is null and participant_id = '00000000-146b-4000-8000-0000000000b2')
       from pg_temp.points('00000000-146b-4000-8000-000000000001', '00000000-146b-4000-8000-0000000000a2')),
    'a month he played without a movement: one row, no entry');
  perform pg_temp.check(
    (select count(*) from pg_temp.points('00000000-146b-4000-8000-000000000002', '00000000-146b-4000-8000-0000000000a2')) = 0,
    'a month he never played: no row');
end $$;

rollback;
