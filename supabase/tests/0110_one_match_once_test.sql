-- End-to-end test of migration 0110: a visible, non-test fixture may not be
-- written while another visible, non-test fixture of the same two sides --
-- either order, the same catalog team or the same name key -- kicks off
-- less than 12 hours from it. Batch 139.
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

-- Whether running p_sql is refused as a second copy of a match.
create function pg_temp.refused(p_sql text) returns boolean
language plpgsql as $$
declare
  v_constraint text;
begin
  execute p_sql;
  return false;
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  return v_constraint = 'fixture_schedules_one_match';
end $$;

insert into football_data.teams (id, name) values
  ('00000000-0110-4000-8000-000000000001', 'ليون'),
  ('00000000-0110-4000-8000-000000000002', 'ليون'),
  ('00000000-0110-4000-8000-000000000003', 'كريستال بالاس'),
  ('00000000-0110-4000-8000-000000000004', 'باير ليفركوزن'),
  ('00000000-0110-4000-8000-000000000005', 'الأهلي'),
  ('00000000-0110-4000-8000-000000000006', 'الأهلي المصري'),
  ('00000000-0110-4000-8000-000000000007', 'الترجي');

do $$
declare
  lyon_a uuid := '00000000-0110-4000-8000-000000000001';
  lyon_b uuid := '00000000-0110-4000-8000-000000000002';
  palace uuid := '00000000-0110-4000-8000-000000000003';
  leverkusen uuid := '00000000-0110-4000-8000-000000000004';
  ahli uuid := '00000000-0110-4000-8000-000000000005';
  ahly uuid := '00000000-0110-4000-8000-000000000006';
  taraji uuid := '00000000-0110-4000-8000-000000000007';
  synced uuid := '00000000-0110-4000-8000-000000000101';
  k timestamptz := '2026-10-15 16:45:00+00';
  n int;
begin
  -- The sync's copy.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (synced, 'ليون', 'كريستال بالاس', k, lyon_b, palace);

  -- 1. The admin's copy, same teams, minutes later (the 2026-10-15 case).
  perform pg_temp.check(pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000201', 'ليون', 'كريستال بالاس', k, lyon_b, palace)),
    'the same two teams at the same time are refused');

  -- 2. The other catalog row of the same club.
  perform pg_temp.check(pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000202', 'ليون', 'كريستال بالاس', k + interval '2 hours', lyon_a, palace)),
    'another catalog row of the same name is refused');

  -- 3. Home and away the other way round.
  perform pg_temp.check(pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000203', 'كريستال بالاس', 'ليون', k, palace, lyon_b)),
    'the same match with the sides swapped is refused');

  -- 4. Typed by hand, no teams, other spelling and spaces.
  perform pg_temp.check(pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
     values (%L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000204', ' ليون ', 'كريستال  بالاس', k)),
    'hand-typed names with the same key are refused');

  -- 5. Thirteen hours away is another match.
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000205', 'ليون', 'كريستال بالاس', k + interval '13 hours', lyon_b, palace)),
    'thirteen hours away is allowed');
  delete from competition.fixture_schedules where fixture_id = '00000000-0110-4000-8000-000000000205';

  -- 6. A different opponent is a different match.
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000206', 'ليون', 'باير ليفركوزن', k, lyon_a, leverkusen)),
    'one side alike, the other different, is allowed');
  delete from competition.fixture_schedules where fixture_id = '00000000-0110-4000-8000-000000000206';

  -- 7. Audit C-04: a name inside another is not the same club.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values ('00000000-0110-4000-8000-000000000207', 'الأهلي المصري', 'الترجي', k, ahly, taraji);
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000208', 'الأهلي', 'الترجي', k, ahli, taraji)),
    'Al Ahli is not Al Ahly (Egypt)');

  -- 8. A test fixture neither is refused nor gets in the way.
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test)
     values (%L, %L, %L, %L, %L, %L, true)',
    '00000000-0110-4000-8000-000000000209', 'ليون', 'كريستال بالاس', k, lyon_b, palace)),
    'a test copy is allowed');

  -- 9. Hiding the sync's copy lets an admin add his own; showing the
  --    hidden one again is then refused.
  perform pg_temp.check(not pg_temp.refused(format(
    'update competition.fixture_schedules set hidden_at = now() where fixture_id = %L', synced)),
    'hiding a copy is never refused');
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)',
    '00000000-0110-4000-8000-000000000210', 'ليون', 'كريستال بالاس', k, lyon_a, palace)),
    'a hidden copy is not in the way');
  perform pg_temp.check(pg_temp.refused(format(
    'update competition.fixture_schedules set hidden_at = null where fixture_id = %L', synced)),
    'showing a hidden copy beside a visible one is refused');

  -- 10. The visible copy keeps working: its own kickoff moves, an upsert
  --     of itself, a league change.
  perform pg_temp.check(not pg_temp.refused(
    'update competition.fixture_schedules set kickoff_at = kickoff_at + interval ''30 minutes''
      where fixture_id = ''00000000-0110-4000-8000-000000000210'''),
    'a fixture''s own kickoff can move');
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
     values (%L, %L, %L, %L, %L, %L)
     on conflict (fixture_id) do update set home_team = excluded.home_team, away_team = excluded.away_team,
       kickoff_at = excluded.kickoff_at, home_team_id = excluded.home_team_id, away_team_id = excluded.away_team_id',
    '00000000-0110-4000-8000-000000000210', 'ليون', 'كريستال بالاس', k + interval '30 minutes', lyon_a, palace)),
    'an upsert of the same fixture is allowed');

  -- 11. A correction that moves another fixture onto this match is refused.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values ('00000000-0110-4000-8000-000000000211', 'ليون', 'كريستال بالاس', k + interval '3 days', lyon_a, palace);
  perform pg_temp.check(pg_temp.refused(format(
    'update competition.fixture_schedules set kickoff_at = %L where fixture_id = %L',
    k + interval '1 hour', '00000000-0110-4000-8000-000000000211')),
    'moving another copy onto the match is refused');

  -- 12. Rows written before 0110 (two visible copies) are left alone: an
  --     update that changes none of their teams or kickoff passes.
  alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values ('00000000-0110-4000-8000-000000000212', 'باير ليفركوزن', 'الترجي', k + interval '5 days', leverkusen, taraji),
         ('00000000-0110-4000-8000-000000000213', 'باير ليفركوزن', 'الترجي', k + interval '5 days', leverkusen, taraji);
  alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;
  perform pg_temp.check(not pg_temp.refused(
    'update competition.fixture_schedules set home_team = home_team
      where fixture_id = ''00000000-0110-4000-8000-000000000212'''),
    'an old copy whose teams and kickoff stay is not refused');
  perform pg_temp.check(not pg_temp.refused(
    'update competition.fixture_schedules set hidden_at = now()
      where fixture_id = ''00000000-0110-4000-8000-000000000213'''),
    'an old copy can be hidden');

  -- 13. The name key folds hamza, alif maqsura, taa marbuta, case, spaces.
  perform pg_temp.check(competition.team_name_key(' الأهلى  ') = 'الاهلي', 'name key folds spelling');
  perform pg_temp.check(competition.team_name_key('Al  Hilal') = competition.team_name_key('al hilal'), 'name key folds case and spaces');

  select count(*) into n from ops.applied_migrations where version = '0110_one_match_once';
  perform pg_temp.check(n = 1, '0110 records itself');
end $$;

rollback;
