-- End-to-end test of migration 0175: a visible, non-test fixture may not be
-- written while another visible, non-test fixture kicks off less than 12
-- hours from it with one of its clubs -- the same catalog team or the same
-- name key -- on either side (script 93). The 2026-10-15 case: "هوفنهايم -
-- بيشتكاش" typed beside the sync's "هوفنهايم - بشكتاش". Rolled back at the
-- end.
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

-- The constraint p_sql is refused on, or 'none'.
create function pg_temp.refusal(p_sql text) returns text
language plpgsql as $$
declare
  v_constraint text;
begin
  execute p_sql;
  return 'none';
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  return v_constraint;
end $$;

create function pg_temp.add(p_id text, p_home text, p_away text, p_kickoff timestamptz,
                            p_home_id uuid, p_away_id uuid, p_test boolean default false)
returns text
language sql as $q$
  select pg_temp.refusal(format(
    'insert into competition.fixture_schedules
       (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test)
     values (%L, %L, %L, %L, %L, %L, %L)',
    p_id, p_home, p_away, p_kickoff, p_home_id, p_away_id, p_test))
$q$;

insert into football_data.teams (id, name) values
  ('00000000-0175-4000-8000-000000000001', 'هوفنهايم'),
  ('00000000-0175-4000-8000-000000000002', 'بشكتاش'),
  ('00000000-0175-4000-8000-000000000003', 'ألكمار'),
  ('00000000-0175-4000-8000-000000000004', 'سلتيك'),
  ('00000000-0175-4000-8000-000000000005', 'بنفيكا');

do $$
declare
  hof uuid := '00000000-0175-4000-8000-000000000001';
  bjk uuid := '00000000-0175-4000-8000-000000000002';
  alk uuid := '00000000-0175-4000-8000-000000000003';
  cel uuid := '00000000-0175-4000-8000-000000000004';
  ben uuid := '00000000-0175-4000-8000-000000000005';
  synced text := '00000000-0175-4000-8000-000000000101';
  k timestamptz := '2099-10-15 19:00:00+00';
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0175_one_club_one_match'),
    '0175 records itself');

  -- The sync's copy.
  perform pg_temp.check(pg_temp.add(synced, 'هوفنهايم', 'بشكتاش', k, hof, bjk) = 'none',
    'the sync adds its match');

  -- 1. The 2026-10-15 case: Hoffenheim picked, the other side misspelt.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000201', 'هوفنهايم', 'بيشتكاش', k, hof, null)
      = 'fixture_schedules_one_club',
    'one club picked, the other misspelt: refused as one club in two matches');

  -- 2. Both typed by hand: Hoffenheim's name key is enough.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000202', 'هوفنهايم ', 'بيشتكاش', k + interval '2 hours', null, null)
      = 'fixture_schedules_one_club',
    'a hand-typed name of a club with a match then is refused');

  -- 3. The club on the other side, the other way round.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000203', 'بنفيكا', 'بشكتاش', k - interval '3 hours', ben, bjk)
      = 'fixture_schedules_one_club',
    'the away club at home in another match is refused');

  -- 4. Both sides alike stays the same match (0110).
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000204', 'بشكتاش', 'هوفنهايم', k, bjk, hof)
      = 'fixture_schedules_one_match',
    'the same match is still told as the same match');

  -- 5. Other clubs the same evening.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000205', 'ألكمار', 'سلتيك', k, alk, cel) = 'none',
    'other clubs the same evening are added');

  -- 6. Thirteen hours away.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000206', 'هوفنهايم', 'بنفيكا', k + interval '13 hours', hof, ben) = 'none',
    'thirteen hours away is another match day');

  -- 7. A test fixture neither is refused nor gets in the way.
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000207', 'هوفنهايم', 'نادي تجريبي', k, hof, null, true) = 'none',
    'a test fixture of a busy club is allowed');

  -- 8. A hidden match is out of the way; showing it again is refused.
  update competition.fixture_schedules set hidden_at = now() where fixture_id = synced::uuid;
  perform pg_temp.check(
    pg_temp.add('00000000-0175-4000-8000-000000000208', 'هوفنهايم', 'بيشتكاش', k, hof, null) = 'none',
    'beside a hidden match the club may be added');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update competition.fixture_schedules set hidden_at = null where fixture_id = %L', synced))
      = 'fixture_schedules_one_club',
    'showing the hidden one again is refused');

  -- 9. A fixture keeps working: its own kickoff moves, a no-op upsert.
  perform pg_temp.check(
    pg_temp.refusal(
      'update competition.fixture_schedules set kickoff_at = kickoff_at + interval ''10 minutes''
        where fixture_id = ''00000000-0175-4000-8000-000000000208''') = 'none',
    'a fixture''s own kickoff can move');

  -- 10. Moving another club onto a busy evening is refused.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update competition.fixture_schedules set away_team = %L, away_team_id = %L
        where fixture_id = %L', 'هوفنهايم', hof, '00000000-0175-4000-8000-000000000205'))
      = 'fixture_schedules_one_club',
    'a correction that puts a busy club in a second match is refused');

  -- 11. Rows written before 0175 sharing a club are left alone.
  alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values ('00000000-0175-4000-8000-000000000211', 'ألكمار', 'بنفيكا', k + interval '1 hour', alk, ben);
  alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;
  perform pg_temp.check(
    pg_temp.refusal(
      'update competition.fixture_schedules set home_team = home_team
        where fixture_id = ''00000000-0175-4000-8000-000000000211''') = 'none',
    'an old row whose teams and kickoff stay is not refused');
  perform pg_temp.check(
    pg_temp.refusal(
      'update competition.fixture_schedules set hidden_at = now()
        where fixture_id = ''00000000-0175-4000-8000-000000000211''') = 'none',
    'and can be hidden');
end $$;

rollback;
