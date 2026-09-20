create or replace view leaderboard.season_fixture_standings as
  with scores as (
    select
      p.season_id,
      fs.participant_id,
      sum(fs.points)::bigint as score_points,
      count(*)::bigint as fixtures_scored,
      count(*) filter (
        where fs.grade = 'exact_scoreline'
      )::bigint as exact_count,
      count(*) filter (
        where fs.grade in ('exact_scoreline', 'correct_outcome', 'incorrect')
      )::bigint as decided_count
    from scoring.fixture_scores fs
    join competition.participants p
      on p.id = fs.participant_id
    group by p.season_id, fs.participant_id
  ),
  bonuses as (
    select
      p.season_id,
      e.participant_id,
      sum(e.amount)::bigint as bonus_points
    from ledger.fixture_point_entries e
    join competition.participants p
      on p.id = e.participant_id
    where e.entry_kind = 'streak_bonus'
      and exists (
        select 1
        from competition.season_fixtures sf
        where sf.season_id = p.season_id
          and sf.fixture_id = e.fixture_id
      )
    group by p.season_id, e.participant_id
  ),
  population as (
    select season_id, participant_id from scores
    union
    select season_id, participant_id from bonuses
  )
  select
    p.season_id,
    p.participant_id,
    (coalesce(s.score_points, 0) + coalesce(b.bonus_points, 0))::bigint as total_points,
    coalesce(s.fixtures_scored, 0)::bigint as fixtures_scored,
    coalesce(s.exact_count, 0)::bigint as exact_count,
    coalesce(s.decided_count, 0)::bigint as decided_count
  from population p
  left join scores s
    on s.season_id = p.season_id
   and s.participant_id = p.participant_id
  left join bonuses b
    on b.season_id = p.season_id
   and b.participant_id = p.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL. It combines already-scored fixture '
  'points with already-awarded streak bonuses from the same append-only '
  'fixture ledger; no points are computed or stored here. The Dart '
  'GetSeasonFixtureLeaderboard uses the same aggregate. decided_count '
  'excludes missed and pending grades.';

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
