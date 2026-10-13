-- ============================================================================
-- Migration 0108: every player gets a place of his own on the month board
--
-- ADDITIVE / MODIFY-ONLY. One view gains a column at its end, one function
-- is redefined (same signature, same schedule), and the ranks of each
-- season's latest daily snapshot are re-ordered among players who were
-- level on points. No point, score, prediction, user or ledger entry is
-- written, changed or removed.
--
-- ## The order (decided 2026-10-14), the same as the Dart FixtureLeaderboard
-- Three players on 45 points all showed tenth. The tie-breaks were points,
-- then the month's invitation points, then exact scorelines (0074); two
-- more now follow:
-- 1. prediction points, most first;
-- 2. the month's invitation points (capped at 20), most first;
-- 3. exact scorelines, most first;
-- 4. right outcomes with the wrong score (`correct_outcome`), most first;
-- 5. the earlier join of the month's contest (`participants.joined_at`).
-- Players share a place only when level on all five -- never, in practice.
--
-- The daily snapshot behind the movement arrows must rank exactly as the
-- board does, or the arrows would show moves that never happened. For the
-- same reason the latest snapshot of every season is re-ordered once here
-- among players who were level on its points: without it, the day this
-- ships, players who shared a place would see arrows pointing down.
--
-- Safe to re-run.
-- ============================================================================

begin;

-- The view keeps its columns, names, types and order; outcome_count is
-- added at the end, so `create or replace view` is enough. The body is
-- 0107's.
create or replace view leaderboard.season_fixture_standings as
  select
    p.season_id,
    fs.participant_id,
    sum(fs.points)::bigint as total_points,
    count(*)::bigint as fixtures_scored,
    count(*) filter (
      where fs.grade = 'exact_scoreline'
    )::bigint as exact_count,
    count(*) filter (
      where fs.grade in ('exact_scoreline', 'correct_outcome', 'incorrect')
    )::bigint as decided_count,
    count(*) filter (
      where fs.grade = 'correct_outcome'
    )::bigint as outcome_count
  from scoring.fixture_scores fs
  join competition.participants p
    on p.id = fs.participant_id
  join identity.users u
    on u.id = p.user_id
  where u.status <> 'suspended'
    and not exists (
      select 1
      from competition.fixture_schedules sch
      where sch.fixture_id = fs.fixture_id
        and (sch.hidden_at is not null or sch.is_test)
    )
  group by p.season_id, fs.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL: already-scored fixture points '
  'only. Streak bonuses are NOT included (0072): they count in the weekly '
  'league alone. Suspended accounts are left out (0085), and so are hidden '
  'and test fixtures (0107). No points are computed or stored here. '
  'decided_count excludes missed and pending grades; outcome_count is the '
  'right outcomes with the wrong score (0108).';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_fixture_standings '
      'set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_fixture_standings from anon;
grant select on leaderboard.season_fixture_standings to authenticated;

create or replace function leaderboard.capture_season_rank_snapshots(
  p_captured_on date default (now() at time zone 'utc')::date
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_rows integer;
begin
  insert into leaderboard.season_rank_snapshots as t
    (season_id, participant_id, captured_on, rank, total_points)
  select
    s.season_id,
    s.participant_id,
    p_captured_on,
    rank() over (
      partition by s.season_id
      order by s.total_points desc,
               coalesce(rm.referral_points, 0) desc,
               s.exact_count desc,
               s.outcome_count desc,
               p.joined_at asc
    ),
    s.total_points
  from leaderboard.season_fixture_standings s
  join competition.seasons cs
    on cs.id = s.season_id
   and cs.start_at <  ((p_captured_on + 1)::timestamp at time zone 'utc')
   and cs.end_at   >  (p_captured_on::timestamp at time zone 'utc')
  join competition.participants p
    on p.id = s.participant_id
  left join gamification.referral_month_points rm
    on rm.season_id = s.season_id
   and rm.user_id = p.user_id
  on conflict (season_id, participant_id, captured_on) do update
    set rank         = excluded.rank,
        total_points = excluded.total_points,
        captured_at  = now();

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function leaderboard.capture_season_rank_snapshots(date) is
  'Captures today''s FIXTURE standings for every open season into '
  'leaderboard.season_rank_snapshots, ranked by points, then the month''s '
  'invitation points, then exact scorelines (0074), then right outcomes, '
  'then the earlier join (0108). Idempotent per day. Returns the row count '
  'written.';

-- The latest snapshot of each season, re-ordered among players who were
-- level on its points. Its points stay as captured: only the order inside
-- a tie changes, by today's tie-break numbers, so a real move stays a move.
with latest as (
  select season_id, max(captured_on) as captured_on
  from leaderboard.season_rank_snapshots
  group by season_id
),
reranked as (
  select
    t.season_id,
    t.participant_id,
    t.captured_on,
    rank() over (
      partition by t.season_id
      order by t.total_points desc,
               coalesce(rm.referral_points, 0) desc,
               coalesce(s.exact_count, 0) desc,
               coalesce(s.outcome_count, 0) desc,
               p.joined_at asc
    ) as new_rank
  from leaderboard.season_rank_snapshots t
  join latest l
    on l.season_id = t.season_id
   and l.captured_on = t.captured_on
  join competition.participants p
    on p.id = t.participant_id
  left join leaderboard.season_fixture_standings s
    on s.season_id = t.season_id
   and s.participant_id = t.participant_id
  left join gamification.referral_month_points rm
    on rm.season_id = t.season_id
   and rm.user_id = p.user_id
)
update leaderboard.season_rank_snapshots t
   set rank = r.new_rank
  from reranked r
 where t.season_id = r.season_id
   and t.participant_id = r.participant_id
   and t.captured_on = r.captured_on
   and t.rank is distinct from r.new_rank;

insert into ops.applied_migrations (version)
values ('0108_board_places_tie_break')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0108_board_places_tie_break';                        -- 1 row
-- select count(*) from information_schema.columns
--  where table_schema = 'leaderboard'
--    and table_name = 'season_fixture_standings'
--    and column_name = 'outcome_count';                                   -- 1
