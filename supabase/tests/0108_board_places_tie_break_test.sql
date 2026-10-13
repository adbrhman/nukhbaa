-- End-to-end test for migration 0108: after points, invitation points and
-- exact scorelines, the daily rank snapshot breaks a tie by right outcomes,
-- then by the earlier join of the month; players share a place only when
-- level on all five. The same order as the Dart FixtureLeaderboard
-- (packages/domain/test/leaderboard/board_places_tie_break_test.dart).
-- Rolled back at the end.
\set ON_ERROR_STOP on
begin;

-- p_exact fixtures called exactly (3 points each), then p_outcome right
-- outcomes (0 points), then wrong calls up to the three fixtures.
create function pg_temp.mk_player(n int, p_exact int, p_outcome int, p_joined timestamptz) returns uuid
language plpgsql as $$
declare
  u uuid := ('00000000-0000-4000-8108-' || lpad(n::text, 12, '0'))::uuid;
  p uuid := ('c8100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
  i int;
begin
  insert into auth.users (id, email, email_confirmed_at) values (u, 'p' || n || '@t.io', now());
  insert into identity.users (id, email, display_name, created_at)
  values (u, 'p' || n || '@t.io', 'P' || n, '2026-09-01');
  insert into competition.participants (id, season_id, user_id, joined_at)
  values (p, 'c8100000-0000-4000-8000-000000000010', u, p_joined);
  for i in 1..3 loop
    insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
    values (('c8100000-0000-4000-8000-0000000000f' || i)::uuid, p, 1,
            case when i <= p_exact then 'exact_scoreline'
                 when i <= p_exact + p_outcome then 'correct_outcome'
                 else 'incorrect' end,
            case when i <= p_exact then 3 else 0 end,
            '2026-10-05 20:00+03');
  end loop;
  return u;
end $$;

insert into competition.competitions (id, name, format, visibility)
values ('c8100000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c8100000-0000-4000-8000-000000000010', 'c8100000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8100000-0000-4000-8000-0000000000f1', 'A', 'B', '2026-10-05 18:00+03'),
  ('c8100000-0000-4000-8000-0000000000f2', 'C', 'D', '2026-10-05 18:00+03'),
  ('c8100000-0000-4000-8000-0000000000f3', 'E', 'F', '2026-10-05 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8100000-0000-4000-8000-000000000010', 'c8100000-0000-4000-8000-0000000000f1', 0),
  ('c8100000-0000-4000-8000-000000000010', 'c8100000-0000-4000-8000-0000000000f2', 1),
  ('c8100000-0000-4000-8000-000000000010', 'c8100000-0000-4000-8000-0000000000f3', 2);

do $$
declare
  rank_of text;
begin
  -- All four: 6 points from two exact calls, no invitations.
  perform pg_temp.mk_player(1, 2, 0, '2026-10-01 09:00+03');
  perform pg_temp.mk_player(2, 2, 1, '2026-10-03 09:00+03');
  perform pg_temp.mk_player(3, 2, 1, '2026-10-02 09:00+03');
  -- P4: exactly like P1, joined at the same instant.
  perform pg_temp.mk_player(4, 2, 0, '2026-10-01 09:00+03');

  if (select outcome_count from leaderboard.season_fixture_standings
       where participant_id = 'c8100000-0000-4000-8000-000000000002') <> 1 then
    raise exception 'FAILED: the standings view must count right outcomes';
  end if;
  raise notice 'ok - the standings view counts right outcomes';

  perform leaderboard.capture_season_rank_snapshots('2026-10-10');
  select string_agg(u.display_name || '=' || s.rank, ' ' order by s.rank, u.display_name)
    into rank_of
    from leaderboard.season_rank_snapshots s
    join competition.participants p on p.id = s.participant_id
    join identity.users u on u.id = p.user_id
   where s.season_id = 'c8100000-0000-4000-8000-000000000010'
     and s.captured_on = '2026-10-10';
  raise notice 'snapshot: %', rank_of;
  if rank_of <> 'P3=1 P2=2 P1=3 P4=3' then
    raise exception 'FAILED: expected P3=1 P2=2 P1=3 P4=3, got %', rank_of;
  end if;
  raise notice 'ok - a right outcome puts P2 and P3 above P1 and P4';
  raise notice 'ok - level on outcomes: the earlier joiner P3 is first';
  raise notice 'ok - level on all five: P1 and P4 share third';
end $$;

rollback;
