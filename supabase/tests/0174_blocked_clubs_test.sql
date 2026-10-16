-- End-to-end test for migration 0174: four clubs never on the schedule
-- (script 92). The names are caught in Arabic and English spellings, a
-- fixture with one is refused by its name or by its catalog team, a hidden
-- one stays hidden, the catalog takes no such club, and
-- PostgresTeamRepository._listAllSql marks the one already filed (keep the
-- body identical to the adapter's constant). Rolled back at the end.
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

-- The SQLSTATE and constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_state text;
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate,
                          v_constraint = constraint_name;
  return v_state || '/' || coalesce(v_constraint, '');
end $$;

-- PostgresTeamRepository._listAllSql
create function pg_temp.list_all()
returns table (id uuid, name text, short_name text, crest_url text,
               league_id uuid, blocked boolean)
language sql as $q$
SELECT id, name, short_name, crest_url, league_id,
       football_data.is_blocked_club(name) AS blocked
FROM football_data.teams
ORDER BY name ASC, id ASC
$q$;

do $$
declare
  n text;
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0174_blocked_clubs'),
    '0174 records itself');

  foreach n in array array[
    'هبوعيل بئر السبع', 'هابوعيل بئر السبع', 'هبوعيل بير السبع',
    'Hapoel Beer Sheva', 'Hapoel Be''er-Sheva FC', 'H. Beer Sheva',
    'مكابي تل أبيب', 'ماكابي تل ابيب', 'Maccabi Tel Aviv', 'Maccabi Tel-Aviv F.C.',
    'بيتار القدس', 'Beitar Jerusalem', 'Betar Jerusalem',
    'هبوعيل تل أبيب', 'هابوعيل تل أبيب', 'Hapoel Tel Aviv', 'Hapoel Tel-Aviv (ISR)'
  ] loop
    perform pg_temp.check(football_data.is_blocked_club(n), 'blocked: ' || n);
  end loop;

  foreach n in array array[
    'هوفنهايم', 'بشكتاش', 'ألكمار', 'Maccabi Haifa', 'Hapoel Haifa',
    'Bnei Yehuda Tel Aviv', 'الهلال', 'Jerusalem FC'
  ] loop
    perform pg_temp.check(not football_data.is_blocked_club(n), 'not blocked: ' || n);
  end loop;
  perform pg_temp.check(not football_data.is_blocked_club(null), 'no name is not blocked');
end $$;

-- A club filed before 0174 (the Europa League seed's), put back as it was.
alter table football_data.teams disable trigger teams_blocked_club;
insert into football_data.teams (id, name, short_name)
values ('c1740000-0000-4000-8000-0000000000b1', 'هابوعيل بئر السبع', 'HAP');
alter table football_data.teams enable trigger teams_blocked_club;
insert into football_data.teams (id, name)
values ('c1740000-0000-4000-8000-0000000000a1', 'نادي 174');

-- And its hidden match of 2026-10-15, as it was before 0174.
alter table competition.fixture_schedules disable trigger fixture_schedules_blocked_club;
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, hidden_at)
values ('c1740000-0000-4000-8000-0000000000f0', 'ألكمار', 'هابوعيل بئر السبع',
        '2099-10-15 16:45Z', null, 'c1740000-0000-4000-8000-0000000000b1', now());
alter table competition.fixture_schedules enable trigger fixture_schedules_blocked_club;

do $$
begin
  perform pg_temp.check(
    pg_temp.refusal($s$insert into competition.fixture_schedules
      (fixture_id, home_team, away_team, kickoff_at)
      values ('c1740000-0000-4000-8000-0000000000f1', 'Maccabi Tel Aviv',
              'نادي 174', '2099-11-01 18:00Z')$s$)
      = '23514/fixture_schedules_blocked_club',
    'a match of a blocked club is refused by its name');

  perform pg_temp.check(
    pg_temp.refusal($s$insert into competition.fixture_schedules
      (fixture_id, home_team, away_team, kickoff_at, away_team_id)
      values ('c1740000-0000-4000-8000-0000000000f2', 'نادي 174', 'بئر',
              '2099-11-02 18:00Z', 'c1740000-0000-4000-8000-0000000000b1')$s$)
      = '23514/fixture_schedules_blocked_club',
    'and by its catalog team, whatever name was typed');

  perform pg_temp.check(
    pg_temp.refusal($s$insert into competition.fixture_schedules
      (fixture_id, home_team, away_team, kickoff_at, hidden_at, is_test)
      values ('c1740000-0000-4000-8000-0000000000f3', 'بيتار القدس', 'نادي 174',
              '2099-11-03 18:00Z', now(), true)$s$)
      = '23514/fixture_schedules_blocked_club',
    'a hidden or test copy is refused too');

  perform pg_temp.check(
    pg_temp.refusal($s$update competition.fixture_schedules
      set kickoff_at = '2099-10-15 17:00Z'
      where fixture_id = 'c1740000-0000-4000-8000-0000000000f0'$s$) = 'none',
    'the hidden match already there may be corrected while hidden');

  perform pg_temp.check(
    pg_temp.refusal($s$update competition.fixture_schedules
      set hidden_at = null
      where fixture_id = 'c1740000-0000-4000-8000-0000000000f0'$s$)
      = '23514/fixture_schedules_blocked_club',
    'and is never shown again');

  perform pg_temp.check(
    pg_temp.refusal($s$insert into competition.fixture_schedules
      (fixture_id, home_team, away_team, kickoff_at)
      values ('c1740000-0000-4000-8000-0000000000f4', 'نادي 174', 'Maccabi Haifa',
              '2099-11-04 18:00Z')$s$) = 'none',
    'a match of other clubs is added as before');

  perform pg_temp.check(
    pg_temp.refusal($s$insert into football_data.teams (name)
      values ('Hapoel Tel Aviv')$s$) = '23514/teams_blocked_club',
    'the catalog takes no blocked club');

  perform pg_temp.check(
    pg_temp.refusal($s$update football_data.teams set name = 'مكابي تل أبيب'
      where id = 'c1740000-0000-4000-8000-0000000000a1'$s$)
      = '23514/teams_blocked_club',
    'nor a rename to one');

  perform pg_temp.check(
    (select l.blocked from pg_temp.list_all() l
      where l.id = 'c1740000-0000-4000-8000-0000000000b1')
    and not (select l.blocked from pg_temp.list_all() l
              where l.id = 'c1740000-0000-4000-8000-0000000000a1'),
    'the catalog read marks the club filed before 0174, and only it');

  perform pg_temp.check(
    not exists (select 1 from competition.fixture_schedules s
                 where s.hidden_at is null
                   and (football_data.is_blocked_club(s.home_team)
                        or football_data.is_blocked_club(s.away_team))),
    'no visible match of a blocked club');
end $$;

rollback;
