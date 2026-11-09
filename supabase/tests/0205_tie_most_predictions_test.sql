-- End-to-end test for migration 0205: the daily rank snapshot breaks a tie
-- on points, exact scorelines and right outcomes by the most predictions
-- made, then by the older account. The same order as the Dart
-- FixtureLeaderboard
-- (packages/domain/test/leaderboard/board_places_tie_break_test.dart).
-- Rolled back at the end.
\set ON_ERROR_STOP on
begin;

-- A player who made p_rows predictions (the first p_rows fixtures), the
-- first p_exact of them called exactly (3 points each), the rest wrong; the
-- account was created at p_created.
create function pg_temp.mk_player(n int, p_rows int, p_exact int, p_created timestamptz) returns uuid
language plpgsql as $$
declare
  u uuid := ('00000000-0000-4000-8205-' || lpad(n::text, 12, '0'))::uuid;
  p uuid := ('c8200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
  i int;
begin
  insert into auth.users (id, email, email_confirmed_at) values (u, 'p' || n || '@t.io', now());
  insert into identity.users (id, email, display_name, created_at)
  values (u, 'p' || n || '@t.io', 'P' || n, p_created);
  insert into competition.participants (id, season_id, user_id, joined_at)
  values (p, 'c8200000-0000-4000-8000-000000000010', u, '2026-10-01 09:00+03');
  for i in 1..p_rows loop
    insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
    values (('c8200000-0000-4000-8000-0000000000f' || i)::uuid, p, 1,
            case when i <= p_exact then 'exact_scoreline' else 'incorrect' end,
            case when i <= p_exact then 3 else 0 end,
            '2026-10-05 20:00+03');
  end loop;
  return u;
end $$;

insert into competition.competitions (id, name, format, visibility)
values ('c8200000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8200000-0000-4000-8000-0000000000f1', 'A', 'B', '2026-10-05 18:00+03'),
  ('c8200000-0000-4000-8000-0000000000f2', 'C', 'D', '2026-10-05 18:00+03'),
  ('c8200000-0000-4000-8000-0000000000f3', 'E', 'F', '2026-10-05 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-0000000000f1', 0),
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-0000000000f2', 1),
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-0000000000f3', 2);

do $$
declare
  rank_of text;
  body text;
begin
  -- All four have 6 points from two exact calls and no right outcome.
  -- P1 made two predictions, the others three.
  perform pg_temp.mk_player(1, 2, 2, '2026-03-01 09:00+03');
  -- P2 and P3 made three: the older account, P3, is first.
  perform pg_temp.mk_player(2, 3, 2, '2026-06-01 09:00+03');
  perform pg_temp.mk_player(3, 3, 2, '2026-05-01 09:00+03');
  -- P4: exactly like P3, created at the same instant.
  perform pg_temp.mk_player(4, 3, 2, '2026-05-01 09:00+03');

  perform leaderboard.capture_season_rank_snapshots('2026-10-10');
  select string_agg(u.display_name || '=' || s.rank, ' ' order by s.rank, u.display_name)
    into rank_of
    from leaderboard.season_rank_snapshots s
    join competition.participants p on p.id = s.participant_id
    join identity.users u on u.id = p.user_id
   where s.season_id = 'c8200000-0000-4000-8000-000000000010'
     and s.captured_on = '2026-10-10';
  raise notice 'snapshot: %', rank_of;
  if rank_of <> 'P3=1 P4=1 P2=3 P1=4' then
    raise exception 'FAILED: expected P3=1 P4=1 P2=3 P1=4, got %', rank_of;
  end if;
  raise notice 'ok - more predictions first, whoever has the older account';
  raise notice 'ok - level on predictions: the older account P3 is above P2';
  raise notice 'ok - level on everything: P3 and P4 share first';

  body := pg_get_functiondef(
    'leaderboard.capture_season_rank_snapshots(date)'::regprocedure);
  if position('decided_count' in body) = 0 then
    raise exception 'FAILED: the snapshot does not read the predictions made';
  end if;
  raise notice 'ok - the snapshot reads the predictions made';
end $$;

rollback;
