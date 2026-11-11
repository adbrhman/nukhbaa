-- Migration 0199 (the month crowns itself, script 204) and the statements
-- PostgresMonthCrownStore runs. Rolled back at the end.
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

create function pg_temp.refused(stmt text, name text, label text)
returns void language plpgsql as $$
declare
  v_name text;
begin
  begin
    execute stmt;
  exception when others then
    get stacked diagnostics v_name = constraint_name;
    perform pg_temp.check(name is null or v_name = name, label || ' (' || coalesce(v_name, sqlerrm) || ')');
    return;
  end;
  raise exception 'FAILED: % (not refused)', label;
end $$;

-- PostgresMonthCrownStore.dueSql
PREPARE crown_due(timestamptz, int) AS
SELECT season_id::text AS season_id, label, end_at, crowned_at
FROM competition.month_crown_due($1::timestamptz, make_interval(hours => $2::int));

-- PostgresMonthCrownStore.stateSql
PREPARE crown_state(uuid, timestamptz, int) AS
SELECT waiting, waiting_names, skipped, skipped_names, last_result_at, rescore
FROM competition.month_crown_state($1::uuid, $2::timestamptz,
                                   make_interval(hours => $3::int));

-- PostgresMonthCrownStore.rescoreSql
PREPARE crown_rescore(uuid) AS
SELECT fixture_id::text AS fixture_id
FROM competition.month_crown_rescore($1::uuid);

-- PostgresMonthCrownStore.prizeSql
PREPARE crown_prize(uuid) AS
SELECT competition.month_prize_for($1::uuid) AS prize;

-- PostgresMonthCrownStore.setPrizeSql
PREPARE set_prize(uuid, text, uuid, timestamptz) AS
INSERT INTO competition.month_prizes (season_id, prize, set_by, set_at)
VALUES ($1::uuid, $2::text, $3::uuid, $4::timestamptz)
ON CONFLICT (season_id) DO UPDATE SET
  prize  = EXCLUDED.prize,
  set_by = EXCLUDED.set_by,
  set_at = EXCLUDED.set_at;

-- PostgresMonthCrownStore.noticeSql
PREPARE crown_notice(uuid, text, text) AS
INSERT INTO competition.month_crown_notices (season_id, kind, signature)
VALUES ($1::uuid, $2::text, $3::text)
ON CONFLICT DO NOTHING
RETURNING kind;

-- PostgresMonthCrownStore.changedSql
PREPARE crown_changed(uuid, timestamptz) AS
SELECT competition.month_results_after($1::uuid, $2::timestamptz) AS written_at;

-- ---------------------------------------------------------------------------
-- A competition with October (crowned by hand, prize 150), November (ended,
-- not crowned) and a league season that is not a month.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select ('a1990000-0000-4000-8000-00000000000' || i)::uuid, 'p' || i || '@x', now()
from generate_series(1, 3) i;
insert into identity.users (id, email, role, status, display_name) values
  ('a1990000-0000-4000-8000-000000000001', 'p1@x', 'admin', 'active', 'Owner'),
  ('a1990000-0000-4000-8000-000000000002', 'p2@x', 'user', 'active', 'P2'),
  ('a1990000-0000-4000-8000-000000000003', 'p3@x', 'user', 'active', 'P3');
insert into competition.competitions (id, name, format, visibility) values
  ('c1990000-0000-4000-8000-000000000001', 'M', 'football_scoreline', 'public'),
  ('c1990000-0000-4000-8000-000000000002', 'L', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('51990000-0000-4000-8000-00000000000a', 'c1990000-0000-4000-8000-000000000001',
   '10/2026', '2026-09-30 21:00+00', '2026-10-31 21:00+00'),
  ('51990000-0000-4000-8000-00000000000b', 'c1990000-0000-4000-8000-000000000001',
   '11/2026', '2026-10-31 21:00+00', '2026-11-30 21:00+00'),
  ('51990000-0000-4000-8000-00000000000c', 'c1990000-0000-4000-8000-000000000002',
   '2026-2027', '2026-08-01 00:00+00', '2026-11-30 21:00+00');
insert into competition.participants (id, season_id, user_id, status, joined_at)
select ('b199000' || s.k || '-0000-4000-8000-00000000000' || u.n)::uuid,
       s.id, ('a1990000-0000-4000-8000-00000000000' || u.n)::uuid, 'active', s.start_at
from (values ('a', '51990000-0000-4000-8000-00000000000a'::uuid, timestamptz '2026-09-30 21:00+00'),
             ('b', '51990000-0000-4000-8000-00000000000b'::uuid, timestamptz '2026-10-31 21:00+00'),
             ('c', '51990000-0000-4000-8000-00000000000c'::uuid, timestamptz '2026-08-01 00:00+00')) s(k, id, start_at)
cross join (values ('1'), ('2'), ('3')) u(n);

-- November's fixtures (kickoffs in UTC):
--   f1 played, result, scored and posted                 -> clean
--   f2 played 30 Nov 19:00, no result yet                -> waiting
--   f3 played 12 Nov, no result                          -> skipped
--   f4 moved to 2 Dec, no result                         -> skipped
--   f5 hidden, no result                                 -> not the board's
--   f6 a test fixture                                    -> not the board's
--   f7 result corrected after its scoring                -> rescore
--   f8 a pending score although the result is in         -> rescore
--   f9 a prediction with no score                        -> rescore
--   fa ledger short of the score (streak bonus ignored)  -> rescore
--   fb ledger equal to the score with a streak bonus     -> clean
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, hidden_at, is_test) values
  ('f1990000-0000-4000-8000-0000000000f1', 'A1', 'B1', '2026-11-10 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f2', 'A2', 'B2', '2026-11-30 19:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f3', 'A3', 'B3', '2026-11-12 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f4', 'A4', 'B4', '2026-12-02 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f5', 'A5', 'B5', '2026-11-30 18:00+00', '2026-11-30 10:00+00', false),
  ('f1990000-0000-4000-8000-0000000000f6', 'A6', 'B6', '2026-11-30 18:30+00', null, true),
  ('f1990000-0000-4000-8000-0000000000f7', 'A7', 'B7', '2026-11-20 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f8', 'A8', 'B8', '2026-11-21 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000f9', 'A9', 'B9', '2026-11-22 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000fa', 'AA', 'BA', '2026-11-23 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000fb', 'AB', 'BB', '2026-11-24 18:00+00', null, false),
  ('f1990000-0000-4000-8000-0000000000e1', 'O1', 'P1', '2026-10-30 18:00+00', null, false);
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select '51990000-0000-4000-8000-00000000000b', fixture_id, 0
  from competition.fixture_schedules
 where fixture_id::text like 'f1990000-0000-4000-8000-0000000000f%';
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('51990000-0000-4000-8000-00000000000a', 'f1990000-0000-4000-8000-0000000000e1', 0),
  ('51990000-0000-4000-8000-00000000000c', 'f1990000-0000-4000-8000-0000000000f1', 0);

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('f1990000-0000-4000-8000-0000000000f1', 1, 0, '2026-11-10 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000f6', 1, 1, '2026-11-30 20:30+00'),
  ('f1990000-0000-4000-8000-0000000000f7', 2, 0, '2026-11-20 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000f8', 0, 0, '2026-11-21 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000f9', 1, 1, '2026-11-22 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000fa', 3, 1, '2026-11-23 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000fb', 0, 2, '2026-11-24 20:00+00'),
  ('f1990000-0000-4000-8000-0000000000e1', 1, 2, '2026-10-30 20:00+00');
-- The results' write times, as the recorders left them (the trigger that
-- stamps now() is off inside this transaction so the times can be set).
alter table scoring.fixture_results disable trigger fixture_results_set_updated_at;
update scoring.fixture_results
   set created_at = recorded_at, updated_at = recorded_at;
update scoring.fixture_results
   set updated_at = '2026-11-20 21:00+00'
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f7';

-- Predictions sent before kickoff, written now: the kickoff guard reads
-- the clock, and these November 2026 kickoffs are past (script 258).
alter table prediction.fixture_predictions
  disable trigger fixture_predictions_reject_write_after_kickoff;
insert into prediction.fixture_predictions (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), f.id::uuid, ('b199000b-0000-4000-8000-00000000000' || u.n)::uuid, 1, 0, false,
       '2026-11-01 10:00+00'
  from (values ('f1990000-0000-4000-8000-0000000000f1'), ('f1990000-0000-4000-8000-0000000000f2'),
               ('f1990000-0000-4000-8000-0000000000f7'), ('f1990000-0000-4000-8000-0000000000f8'),
               ('f1990000-0000-4000-8000-0000000000f9'), ('f1990000-0000-4000-8000-0000000000fa'),
               ('f1990000-0000-4000-8000-0000000000fb')) f(id)
 cross join (values ('2'), ('3')) u(n);

-- Scores: every prediction scored after its result, except as listed.
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
select fp.fixture_id, fp.participant_id, 4,
       case when r.home_goals = 1 and r.away_goals = 0 then 'exact_scoreline' else 'incorrect' end,
       case when r.home_goals = 1 and r.away_goals = 0 then 3 else 0 end,
       r.recorded_at + interval '1 minute'
  from prediction.fixture_predictions fp
  join scoring.fixture_results r on r.fixture_id = fp.fixture_id
 where fp.fixture_id <> 'f1990000-0000-4000-8000-0000000000f9';
update scoring.fixture_scores set grade = 'pending', points = 0
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f8'
   and participant_id = 'b199000b-0000-4000-8000-000000000002';
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
values ('f1990000-0000-4000-8000-0000000000f9', 'b199000b-0000-4000-8000-000000000002', 4, 'incorrect', 0,
        '2026-11-22 20:01+00');
-- (f9's player 3 has no score.)

-- The ledger: what each score posted; fa's player 2 got 0 for 3 points;
-- fb's player 2 also has a streak bonus that is not part of the score.
insert into ledger.fixture_point_entries (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
select gen_random_uuid(), sc.participant_id, sc.fixture_id, 'fixture_score',
       case when sc.fixture_id = 'f1990000-0000-4000-8000-0000000000fa'
             and sc.participant_id = 'b199000b-0000-4000-8000-000000000002'
            then 0 else sc.points end,
       'fixture_score:' || sc.fixture_id || ':' || sc.participant_id, sc.scored_at
  from scoring.fixture_scores sc;
update scoring.fixture_scores set grade = 'exact_scoreline', points = 3
 where fixture_id = 'f1990000-0000-4000-8000-0000000000fa'
   and participant_id = 'b199000b-0000-4000-8000-000000000002';
insert into ledger.fixture_point_entries (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
values (gen_random_uuid(), 'b199000b-0000-4000-8000-000000000002', 'f1990000-0000-4000-8000-0000000000fb',
        'streak_bonus', 5, 'streak:fb', '2026-11-24 21:00+00');

-- October was crowned by hand at 00:19 on 1 November with 150.
insert into competition.month_champions (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by, prize)
values ('51990000-0000-4000-8000-00000000000a', 'a1990000-0000-4000-8000-000000000002', 3, 1, 1,
        '2026-10-31 21:19+00', 'a1990000-0000-4000-8000-000000000001', '150 ريال');

-- ---------------------------------------------------------------------------
-- The months to look at.
-- ---------------------------------------------------------------------------
create temp table due as
select * from competition.month_crown_due('2026-12-01 00:00+00', interval '10 days');
select pg_temp.check(
  (select array_agg(label order by end_at)::text from due) = '{11/2026}',
  'a month ended 3 hours ago is due; October (a month before) and the league are not');
select pg_temp.check(
  (select crowned_at from due) is null, 'November is not crowned yet');
select pg_temp.check(
  (select count(*) from competition.month_crown_due('2026-11-02 00:00+00', interval '10 days')
    where label = '10/2026') = 0,
  'October, crowned by hand before 0199, is left alone even within its window');
select pg_temp.check(
  (select count(*) from competition.month_crown_due('2026-11-30 20:00+00', interval '10 days')
    where label = '11/2026') = 0,
  'a month not over yet is not due');

EXECUTE crown_due('2026-12-01 00:00+00', 240);

-- ---------------------------------------------------------------------------
-- Where November stands at 1 December 00:00 UTC (03:00 Riyadh).
-- ---------------------------------------------------------------------------
create temp table st as
select * from competition.month_crown_state(
  '51990000-0000-4000-8000-00000000000b', '2026-12-01 00:00+00', interval '6 hours');
select pg_temp.check((select waiting from st) = 1, 'f2 (30 Nov 19:00, no result) is waited for');
select pg_temp.check((select waiting_names from st) = 'A2 × B2', 'the waited match is named');
select pg_temp.check((select skipped from st) = 2, 'f3 (long ago) and f4 (moved out) do not count');
select pg_temp.check((select skipped_names from st) = 'A3 × B3، A4 × B4', 'the skipped matches are named, by kickoff');
select pg_temp.check((select last_result_at from st) = '2026-11-24 20:00+00',
  'the latest result write of the board''s fixtures (the test fixture''s is not one)');
select pg_temp.check((select rescore from st) = 4, 'four results have points not all in');

EXECUTE crown_state('51990000-0000-4000-8000-00000000000b', '2026-12-01 00:00+00', 6);

select pg_temp.check(
  (select waiting from competition.month_crown_state(
     '51990000-0000-4000-8000-00000000000b', '2026-12-01 01:01+00', interval '6 hours')) = 0,
  'six hours after its kickoff f2 counts as postponed');

create temp table rs as
select * from competition.month_crown_rescore('51990000-0000-4000-8000-00000000000b');
select pg_temp.check(
  (select array_agg(fixture_id::text order by fixture_id::text) from rs)
  = array['f1990000-0000-4000-8000-0000000000f7', 'f1990000-0000-4000-8000-0000000000f8',
          'f1990000-0000-4000-8000-0000000000f9', 'f1990000-0000-4000-8000-0000000000fa'],
  'rescore: a corrected result, a pending score, a missing score, a short ledger; not the streak bonus');

EXECUTE crown_rescore('51990000-0000-4000-8000-00000000000b');

-- Once scored again (as ScoreFixture and PostFixtureToLedger would), clean.
update scoring.fixture_scores set scored_at = '2026-11-20 21:01+00'
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f7';
update scoring.fixture_scores set grade = 'incorrect', points = 0
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f8';
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
values ('f1990000-0000-4000-8000-0000000000f9', 'b199000b-0000-4000-8000-000000000003', 4, 'incorrect', 0,
        '2026-11-22 20:01+00');
insert into ledger.fixture_point_entries (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
values (gen_random_uuid(), 'b199000b-0000-4000-8000-000000000002', 'f1990000-0000-4000-8000-0000000000fa',
        'correction', 3, 'fixture_score_correction:fa:2:1', '2026-11-23 21:00+00');
select pg_temp.check(
  (select count(*) from competition.month_crown_rescore('51990000-0000-4000-8000-00000000000b')) = 0,
  'scored again and posted, nothing is left to rescore');

-- ---------------------------------------------------------------------------
-- The prize.
-- ---------------------------------------------------------------------------
select pg_temp.check(
  (select prize from competition.month_prize_for('51990000-0000-4000-8000-00000000000b') prize) = '150 ريال',
  'no prize set ahead: the previous month''s champion prize');
EXECUTE set_prize('51990000-0000-4000-8000-00000000000b', '200 ريال', 'a1990000-0000-4000-8000-000000000001',
                  '2026-11-20 10:00+00');
EXECUTE set_prize('51990000-0000-4000-8000-00000000000b', '250 ريال', 'a1990000-0000-4000-8000-000000000001',
                  '2026-11-21 10:00+00');
select pg_temp.check(
  (select prize || '|' || set_at::text from competition.month_prizes
    where season_id = '51990000-0000-4000-8000-00000000000b') = '250 ريال|2026-11-21 10:00:00+00',
  'the prize set ahead is replaced while the month is not crowned');
EXECUTE crown_prize('51990000-0000-4000-8000-00000000000b');
select pg_temp.check(
  (select competition.month_prize_for('51990000-0000-4000-8000-00000000000b')) = '250 ريال',
  'the prize set ahead comes first');
select pg_temp.check(
  (select competition.month_prize_for('51990000-0000-4000-8000-00000000000a')) is null,
  'the first month has no earlier prize to fall back on');
select pg_temp.refused(
  $q$insert into competition.month_prizes (season_id, prize, set_by)
     values ('51990000-0000-4000-8000-00000000000a', '100', 'a1990000-0000-4000-8000-000000000001')$q$,
  'month_prizes_not_crowned', 'no prize is set for a crowned month');
select pg_temp.refused(
  $q$insert into competition.month_prizes (season_id, prize, set_by)
     values ('51990000-0000-4000-8000-00000000000c', '   ', 'a1990000-0000-4000-8000-000000000001')$q$,
  'month_prizes_prize_check', 'a blank prize is refused');

-- ---------------------------------------------------------------------------
-- Notices: once each.
-- ---------------------------------------------------------------------------
create temp table n1 as
with ins as (
  insert into competition.month_crown_notices (season_id, kind, signature)
  values ('51990000-0000-4000-8000-00000000000b', 'tie', 'u2,u3')
  on conflict do nothing returning kind)
select count(*) as c from ins;
create temp table n2 as
with ins as (
  insert into competition.month_crown_notices (season_id, kind, signature)
  values ('51990000-0000-4000-8000-00000000000b', 'tie', 'u2,u3')
  on conflict do nothing returning kind)
select count(*) as c from ins;
select pg_temp.check((select c from n1) = 1 and (select c from n2) = 0, 'a notice is written once');
EXECUTE crown_notice('51990000-0000-4000-8000-00000000000b', 'crowned', 'u2');
select pg_temp.refused(
  $q$insert into competition.month_crown_notices (season_id, kind, signature)
     values ('51990000-0000-4000-8000-00000000000b', 'other', 'x')$q$,
  'month_crown_notices_kind_check', 'an unknown kind is refused');

-- ---------------------------------------------------------------------------
-- A result written after the crowning.
-- ---------------------------------------------------------------------------
select pg_temp.check(
  (select competition.month_results_after('51990000-0000-4000-8000-00000000000a', '2026-10-31 21:19+00')) is null,
  'October was crowned before 0199: never looked at again');
select pg_temp.check(
  (select competition.month_results_after('51990000-0000-4000-8000-00000000000b', '2099-01-01 00:00+00')) is null,
  'no result written after a crowning made after 0199');
update scoring.fixture_results
   set updated_at = '2099-01-01 01:00+00'
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f1';
EXECUTE crown_changed('51990000-0000-4000-8000-00000000000b', '2099-01-01 00:00+00');
select pg_temp.check(
  (select competition.month_results_after('51990000-0000-4000-8000-00000000000b', '2099-01-01 00:00+00'))
    = '2099-01-01 01:00+00',
  'a result corrected after a crowning made after 0199 is seen, with its time');
update scoring.fixture_results
   set updated_at = '2099-01-01 02:00+00'
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f6';
update scoring.fixture_results
   set updated_at = recorded_at
 where fixture_id = 'f1990000-0000-4000-8000-0000000000f1';
select pg_temp.check(
  (select competition.month_results_after('51990000-0000-4000-8000-00000000000b', '2099-01-01 00:00+00')) is null,
  'a test fixture''s result does not count');

-- A month crowned after 0199 is looked at again, with its crowning time.
insert into competition.month_champions (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by, prize)
values ('51990000-0000-4000-8000-00000000000b', 'a1990000-0000-4000-8000-000000000003', 3, 1, 1,
        '2099-01-01 00:00+00', 'a1990000-0000-4000-8000-000000000001', '250 ريال');
select pg_temp.check(
  (select crowned_at from competition.month_crown_due('2026-12-01 00:00+00', interval '10 days')
    where label = '11/2026') = '2099-01-01 00:00+00',
  'a month crowned after 0199 is still due, with its crowning time');
select pg_temp.refused(
  $q$EXECUTE set_prize('51990000-0000-4000-8000-00000000000b', '300', 'a1990000-0000-4000-8000-000000000001', '2099-01-02')$q$,
  'month_prizes_not_crowned', 'the prize set ahead is frozen once the month is crowned');

-- ---------------------------------------------------------------------------
-- Server only.
-- ---------------------------------------------------------------------------
select pg_temp.check(
  not has_function_privilege('authenticated', 'competition.month_crown_due(timestamptz, interval)', 'execute')
  and not has_function_privilege('anon', 'competition.month_prize_for(uuid)', 'execute'),
  'no client may call the functions');
select pg_temp.check(
  not has_table_privilege('authenticated', 'competition.month_prizes', 'select')
  and not has_table_privilege('anon', 'competition.month_crown_notices', 'insert'),
  'no client may read or write the tables');

rollback;
