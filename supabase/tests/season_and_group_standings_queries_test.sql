-- End-to-end test of the two season boards that used to read the empty
-- round-era ledger (audit C-01): PostgresLeaderboardRepository.
-- _selectSeasonStandingsSql (the "season points" tab) and
-- PostgresGroupRepository._selectGroupSeasonStandingsSql (a group's season
-- board), parameters inlined as function arguments -- keep each body
-- identical to the adapter's constant. A member with scored fixtures shows
-- their points, one with none shows 0, a suspended account and a
-- non-member stay out, and the movement arrow reads the latest snapshot.
-- No migration: the queries read 0019, 0030, 0034 and 0085 objects.
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

-- PostgresLeaderboardRepository._selectSeasonStandingsSql
create function pg_temp.season_board(p_season uuid)
returns table (participant_id uuid, display_name text, total_points bigint,
               entry_count bigint, joined_at timestamptz, previous_rank int,
               exact_count bigint, settled_count bigint,
               outcome_count bigint)
language sql as $q$
SELECT p.id AS participant_id,
       u.display_name AS display_name,
       COALESCE(f.total_points, 0)::bigint AS total_points,
       COALESCE(f.fixtures_scored, 0)::bigint AS entry_count,
       p.joined_at AS joined_at,
       snap.rank AS previous_rank,
       COALESCE(f.exact_count, 0)::bigint AS exact_count,
       COALESCE(f.decided_count, 0)::bigint AS settled_count,
       COALESCE(f.outcome_count, 0)::bigint AS outcome_count
FROM competition.participants p
JOIN identity.users u ON u.id = p.user_id
LEFT JOIN leaderboard.season_fixture_standings f ON f.participant_id = p.id
LEFT JOIN leaderboard.season_rank_snapshots snap
  ON snap.season_id = p.season_id
 AND snap.participant_id = p.id
 AND snap.captured_on = (
       SELECT max(x.captured_on)
       FROM leaderboard.season_rank_snapshots x
       WHERE x.season_id = p.season_id
     )
WHERE p.season_id = p_season
  AND u.status <> 'suspended'
$q$;

-- PostgresGroupRepository._selectGroupSeasonStandingsSql
create function pg_temp.group_board(p_group uuid, p_season uuid)
returns table (participant_id uuid, user_id uuid, display_name text,
               total_points bigint, entry_count bigint, joined_at timestamptz,
               exact_count bigint, settled_count bigint,
               outcome_count bigint)
language sql as $q$
SELECT
  p.id         AS participant_id,
  p.user_id    AS user_id,
  u.display_name AS display_name,
  COALESCE(f.total_points, 0)::bigint    AS total_points,
  COALESCE(f.fixtures_scored, 0)::bigint AS entry_count,
  p.joined_at  AS joined_at,
  COALESCE(f.exact_count, 0)::bigint     AS exact_count,
  COALESCE(f.decided_count, 0)::bigint   AS settled_count,
  COALESCE(f.outcome_count, 0)::bigint   AS outcome_count
FROM competition.participants p
JOIN "group".group_memberships m ON m.user_id = p.user_id
JOIN identity.users u ON u.id = p.user_id
LEFT JOIN leaderboard.season_fixture_standings f ON f.participant_id = p.id
WHERE p.season_id = p_season
  AND m.group_id = p_group
  AND u.status <> 'suspended'
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0c01-4000-8000-000000000001', 'c01a@t.io', now()),
  ('00000000-0c01-4000-8000-000000000002', 'c01b@t.io', now()),
  ('00000000-0c01-4000-8000-000000000003', 'c01c@t.io', now()),
  ('00000000-0c01-4000-8000-000000000004', 'c01d@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0c01-4000-8000-000000000001', 'c01a@t.io', 'Scorer'),
  ('00000000-0c01-4000-8000-000000000002', 'c01b@t.io', 'Newcomer'),
  ('00000000-0c01-4000-8000-000000000003', 'c01c@t.io', 'Outsider'),
  ('00000000-0c01-4000-8000-000000000004', 'c01d@t.io', 'Suspended');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0c01-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-0000000000c1',
        '06/2099', '2099-06-01', '2099-07-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0c01-4000-8000-0000000000a1', '00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-000000000001', '2099-06-01'),
  ('00000000-0c01-4000-8000-0000000000a2', '00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-000000000002', '2099-06-02'),
  ('00000000-0c01-4000-8000-0000000000a3', '00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-000000000003', '2099-06-01'),
  ('00000000-0c01-4000-8000-0000000000a4', '00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-000000000004', '2099-06-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('00000000-0c01-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2099-06-10 18:00+03'),
  ('00000000-0c01-4000-8000-0000000000f2', 'Ahli', 'Ittihad', '2099-06-11 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-0000000000f1', 0),
  ('00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-0000000000f2', 1);
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('00000000-0c01-4000-8000-0000000000f1', '00000000-0c01-4000-8000-0000000000a1', 1, 'exact_scoreline', 6),
  ('00000000-0c01-4000-8000-0000000000f2', '00000000-0c01-4000-8000-0000000000a1', 1, 'incorrect', 0),
  ('00000000-0c01-4000-8000-0000000000f1', '00000000-0c01-4000-8000-0000000000a3', 1, 'exact_scoreline', 3),
  ('00000000-0c01-4000-8000-0000000000f1', '00000000-0c01-4000-8000-0000000000a4', 1, 'exact_scoreline', 3);
insert into leaderboard.season_rank_snapshots (season_id, participant_id, captured_on, rank, total_points) values
  ('00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-0000000000a1', '2099-06-10', 3, 0),
  ('00000000-0c01-4000-8000-0000000000e1', '00000000-0c01-4000-8000-0000000000a1', '2099-06-11', 2, 6);
insert into "group".groups (id, owner_id, name, invite_code) values
  ('00000000-0c01-4000-8000-0000000000b1', '00000000-0c01-4000-8000-000000000001', 'Friends', 'C01ABCDE');
insert into "group".group_memberships (id, group_id, user_id, role) values
  ('00000000-0c01-4000-8000-0000000000d1', '00000000-0c01-4000-8000-0000000000b1', '00000000-0c01-4000-8000-000000000001', 'owner'),
  ('00000000-0c01-4000-8000-0000000000d2', '00000000-0c01-4000-8000-0000000000b1', '00000000-0c01-4000-8000-000000000002', 'member'),
  ('00000000-0c01-4000-8000-0000000000d4', '00000000-0c01-4000-8000-0000000000b1', '00000000-0c01-4000-8000-000000000004', 'member');
update identity.users set status = 'suspended'
 where id = '00000000-0c01-4000-8000-000000000004';

do $$
declare
  season uuid := '00000000-0c01-4000-8000-0000000000e1';
  grp uuid := '00000000-0c01-4000-8000-0000000000b1';
  scorer uuid := '00000000-0c01-4000-8000-0000000000a1';
  newcomer uuid := '00000000-0c01-4000-8000-0000000000a2';
  outsider uuid := '00000000-0c01-4000-8000-0000000000a3';
begin
  -- The season tab.
  perform pg_temp.check(
    (select total_points from pg_temp.season_board(season) where participant_id = scorer) = 6,
    'season board: scored fixtures show their points, not 0');
  perform pg_temp.check(
    (select entry_count from pg_temp.season_board(season) where participant_id = scorer) = 2
    and (select exact_count from pg_temp.season_board(season) where participant_id = scorer) = 1
    and (select settled_count from pg_temp.season_board(season) where participant_id = scorer) = 2,
    'season board: fixtures, exact hits and decided fixtures counted');
  perform pg_temp.check(
    (select total_points from pg_temp.season_board(season) where participant_id = newcomer) = 0
    and (select previous_rank from pg_temp.season_board(season) where participant_id = newcomer) is null,
    'season board: nothing scored reads 0 with no arrow');
  perform pg_temp.check(
    (select previous_rank from pg_temp.season_board(season) where participant_id = scorer) = 2,
    'season board: the arrow compares with the latest snapshot');
  perform pg_temp.check(
    (select count(*) from pg_temp.season_board(season)) = 3,
    'season board: every participant once, the suspended one left out');
  perform pg_temp.check(
    (select total_points from pg_temp.season_board(season) where participant_id = outsider) = 3,
    'season board: the same totals as the monthly store');

  -- A group's season board.
  perform pg_temp.check(
    (select total_points from pg_temp.group_board(grp, season) where participant_id = scorer) = 6,
    'group board: a member with scored fixtures shows their points');
  perform pg_temp.check(
    (select total_points from pg_temp.group_board(grp, season) where participant_id = newcomer) = 0,
    'group board: a member with nothing scored reads 0');
  perform pg_temp.check(
    (select count(*) from pg_temp.group_board(grp, season)) = 2
    and not exists (select 1 from pg_temp.group_board(grp, season) where participant_id = outsider),
    'group board: members only, the suspended member left out');

  -- Batch 134: the month board's tie-breaks travel with both boards.
  update scoring.fixture_scores set grade = 'correct_outcome'
   where participant_id = scorer
     and fixture_id = '00000000-0c01-4000-8000-0000000000f2';
  perform pg_temp.check(
    (select outcome_count from pg_temp.season_board(season) where participant_id = scorer) = 1,
    'season board: right outcomes are read');
  perform pg_temp.check(
    (select exact_count from pg_temp.group_board(grp, season) where participant_id = scorer) = 1
    and (select settled_count from pg_temp.group_board(grp, season) where participant_id = scorer) = 2
    and (select outcome_count from pg_temp.group_board(grp, season) where participant_id = scorer) = 1,
    'group board: exact hits, decided fixtures and right outcomes are read');
end $$;

rollback;
