-- 0211: every write of a prediction is kept, append-only and backend-only,
-- and supabase/queries/prediction_changes.sql reads it back. A player saves
-- 5-1 with the app's own INSERT, changes it to 5-0, turns the double on,
-- saves the same again; another player's prediction is deleted. Rolled
-- back.
\set ON_ERROR_STOP on
\set changes_sql `sed -e 's/--.*$//' -e "s/'%علوش%'/'%Tester 211%'/" -e "s/'%المغرب%'/'%Morocco 211%'/" supabase/queries/prediction_changes.sql | tr '\n' ' ' | sed -e 's/; *$//'`
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

insert into competition.competitions (id, name, format, visibility) values
  ('c2110000-0000-4000-8000-000000000001', 'Monthly 211', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2110000-0000-4000-8000-000000000002', 'c2110000-0000-4000-8000-000000000001',
   '11/2097', '2097-10-31 21:00Z', '2097-11-30 21:00Z');
insert into auth.users (id, email, email_confirmed_at) values
  ('c2110000-0000-4000-8000-000000000003', 't1@nk211.io', now()),
  ('c2110000-0000-4000-8000-000000000004', 't2@nk211.io', now());
insert into identity.users (id, email, display_name) values
  ('c2110000-0000-4000-8000-000000000003', 't1@nk211.io', 'Tester 211'),
  ('c2110000-0000-4000-8000-000000000004', 't2@nk211.io', 'Other 211');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c2110000-0000-4000-8000-000000000005', 'c2110000-0000-4000-8000-000000000002',
   'c2110000-0000-4000-8000-000000000003', now()),
  ('c2110000-0000-4000-8000-000000000006', 'c2110000-0000-4000-8000-000000000002',
   'c2110000-0000-4000-8000-000000000004', now());
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c2110000-0000-4000-8000-000000000007', 'Morocco 211', 'Niger 211', '2097-11-13 20:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c2110000-0000-4000-8000-000000000002', 'c2110000-0000-4000-8000-000000000007', 1);

-- The app's own statements (PostgresFixturePredictionRepository), values
-- in place of its parameters.
INSERT INTO prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double,
   submitted_at)
VALUES ('c2110000-0000-4000-8000-000000000008', 'c2110000-0000-4000-8000-000000000007',
        'c2110000-0000-4000-8000-000000000005', 5, 1, false, now());
UPDATE prediction.fixture_predictions
SET home_goals = 5,
    away_goals = 0,
    is_double  = false,
    submitted_at = now()
WHERE id = 'c2110000-0000-4000-8000-000000000008'
RETURNING id;
UPDATE prediction.fixture_predictions
SET home_goals = 5,
    away_goals = 0,
    is_double  = true,
    submitted_at = now()
WHERE id = 'c2110000-0000-4000-8000-000000000008'
RETURNING id;
UPDATE prediction.fixture_predictions
SET home_goals = 5,
    away_goals = 0,
    is_double  = true,
    submitted_at = now()
WHERE id = 'c2110000-0000-4000-8000-000000000008'
RETURNING id;
INSERT INTO prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double,
   submitted_at)
VALUES ('c2110000-0000-4000-8000-000000000009', 'c2110000-0000-4000-8000-000000000007',
        'c2110000-0000-4000-8000-000000000006', 2, 2, false, now());
delete from prediction.fixture_predictions
 where id = 'c2110000-0000-4000-8000-000000000009';

do $$
declare
  v_rows text[];
begin
  select array_agg(op || ' ' || coalesce(old_home || '-' || old_away || ' ' || old_double, '.')
                   || ' > ' || coalesce(new_home || '-' || new_away || ' ' || new_double, '.')
                   order by id)
    into v_rows
    from prediction.fixture_prediction_changes
   where prediction_id = 'c2110000-0000-4000-8000-000000000008';
  perform pg_temp.check(
    v_rows = array['insert . > 5-1 false', 'update 5-1 false > 5-0 false',
                   'update 5-0 false > 5-0 true', 'update 5-0 true > 5-0 true'],
    'the first save, the change, the double and the same save again are kept');
  perform pg_temp.check(
    (select array_agg(op order by id) from prediction.fixture_prediction_changes
      where prediction_id = 'c2110000-0000-4000-8000-000000000009')
      = array['insert', 'delete'],
    'a deleted prediction keeps its insert and its delete');
  perform pg_temp.check(
    (select bool_and(source ~* '^\s*(insert\s+into|update)\s+prediction\.fixture_predictions')
       from prediction.fixture_prediction_changes
      where prediction_id = 'c2110000-0000-4000-8000-000000000008'),
    'each line keeps the statement that wrote it');
  perform pg_temp.check(
    (select bool_and(changed_at is not null and fixture_id = 'c2110000-0000-4000-8000-000000000007'
                     and old_fixture_id is null)
       from prediction.fixture_prediction_changes
      where prediction_id = 'c2110000-0000-4000-8000-000000000008'),
    'each line has its time and its match');
end $$;

-- Append-only.
do $$
begin
  begin
    update prediction.fixture_prediction_changes set new_home = 9
     where prediction_id = 'c2110000-0000-4000-8000-000000000008';
    raise exception 'FAILED: an update of the log went through';
  exception when check_violation then
    perform pg_temp.check(true, 'the log refuses an update');
  end;
  begin
    delete from prediction.fixture_prediction_changes
     where prediction_id = 'c2110000-0000-4000-8000-000000000008';
    raise exception 'FAILED: a delete of the log went through';
  exception when check_violation then
    perform pg_temp.check(true, 'the log refuses a delete');
  end;
end $$;

-- Backend-only.
do $$
begin
  perform pg_temp.check(
    not has_table_privilege('authenticated', 'prediction.fixture_prediction_changes', 'select')
      and not has_table_privilege('anon', 'prediction.fixture_prediction_changes', 'select')
      and (select relrowsecurity from pg_class
            where oid = 'prediction.fixture_prediction_changes'::regclass),
    'no client reads the log, RLS on');
end $$;

-- The owner's query, as it is.
create temp table changes_out as :changes_sql;
do $$
begin
  perform pg_temp.check(
    (select array_agg("العملية" || ' ' || "قبل" || ' > ' || "بعد" || ' | ' || "من"
                      order by ctid)
       from changes_out where "من" <> 'المحفوظ الآن')
      = array['أول حفظ - > 5-1 | التطبيق (حساب اللاعب)',
              'تعديل 5-1 > 5-0 | التطبيق (حساب اللاعب)',
              'تعديل 5-0 > 5-0 ×2 | التطبيق (حساب اللاعب)',
              'تعديل 5-0 ×2 > 5-0 ×2 | التطبيق (حساب اللاعب)']
      and (select count(*) from changes_out where "من" = 'المحفوظ الآن'
             and "بعد" = '5-0 ×2') = 1
      and (select count(*) from changes_out) = 5,
    'the owner''s query lists the four writes in order, then the stored one');
end $$;

rollback;
