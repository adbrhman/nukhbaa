-- PostgresFixtureMerger._copiesSql (script 95, migration 0176): a fixture
-- first, then the other non-test copies of its match less than 12 hours
-- from it with one of its clubs, not merged yet, each with its counts. The
-- parameter is inlined as the function's argument; keep the body identical
-- to the adapter's constant. Rolled back at the end.
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

create function pg_temp.copies(p_fixture_id uuid)
returns table (fixture_id text, home_team text, away_team text,
               kickoff_at timestamptz, hidden boolean, predictions int,
               doubles int, has_result boolean, linked boolean, is_self boolean)
language sql as $q$
WITH me AS (
  SELECT s.*,
         competition.team_name_key(s.home_team) AS h,
         competition.team_name_key(s.away_team) AS a
  FROM competition.fixture_schedules s
  WHERE s.fixture_id = p_fixture_id
)
SELECT s.fixture_id::text AS fixture_id,
       s.home_team,
       s.away_team,
       s.kickoff_at,
       s.hidden_at IS NOT NULL AS hidden,
       (SELECT count(*) FROM prediction.fixture_predictions fp
         WHERE fp.fixture_id = s.fixture_id)::int AS predictions,
       (SELECT count(*) FROM prediction.fixture_predictions fp
         WHERE fp.fixture_id = s.fixture_id AND fp.is_double)::int AS doubles,
       EXISTS (SELECT 1 FROM scoring.fixture_results r
                WHERE r.fixture_id = s.fixture_id) AS has_result,
       EXISTS (SELECT 1 FROM football_data.external_identity_map m
                WHERE m.canonical_table = 'fixture'
                  AND m.canonical_id = s.fixture_id) AS linked,
       s.fixture_id = me.fixture_id AS is_self
FROM me
JOIN competition.fixture_schedules s
  ON s.fixture_id = me.fixture_id
  OR (NOT me.is_test
      AND NOT s.is_test
      AND s.kickoff_at > me.kickoff_at - interval '12 hours'
      AND s.kickoff_at < me.kickoff_at + interval '12 hours'
      AND NOT EXISTS (SELECT 1 FROM competition.fixture_merges fm
                       WHERE fm.duplicate_fixture_id = s.fixture_id)
      AND COALESCE(
            (s.home_team_id IS NOT NULL
               AND s.home_team_id IN (me.home_team_id, me.away_team_id))
            OR (s.away_team_id IS NOT NULL
               AND s.away_team_id IN (me.home_team_id, me.away_team_id))
            OR competition.team_name_key(s.home_team) IN (me.h, me.a)
            OR competition.team_name_key(s.away_team) IN (me.h, me.a),
            false))
ORDER BY s.fixture_id = me.fixture_id DESC, s.kickoff_at, s.fixture_id
LIMIT 20
$q$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1950000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1950000-0000-4000-8000-000000000010', 'c1950000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
insert into football_data.teams (id, name) values
  ('00000000-0195-4000-8000-000000000001', 'ليخ بوزنان'),
  ('00000000-0195-4000-8000-000000000002', 'ليفركوزن');

alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
-- K kept (linked, a result), D its copy (one side typed), H hidden copy,
-- M a copy already merged, T a test copy, F far (13 h), O other clubs.
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test, hidden_at)
values
  ('c1950000-0000-4000-8000-0000000000a0', 'ليخ بوزنان', 'ليفركوزن', '2099-06-01 19:00Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002', false, null),
  ('c1950000-0000-4000-8000-0000000000d0', 'ليش بوزنان', 'ليفركوزن', '2099-06-01 19:00Z',
   null, '00000000-0195-4000-8000-000000000002', false, null),
  ('c1950000-0000-4000-8000-0000000000b0', 'ليخ بوزنان', 'ليفركوزن ', '2099-06-01 20:00Z',
   '00000000-0195-4000-8000-000000000001', null, false, now()),
  ('c1950000-0000-4000-8000-0000000000c0', 'ليخ بوزنان', 'ليفركوزن', '2099-06-01 18:00Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002', false, now()),
  ('c1950000-0000-4000-8000-0000000000f0', 'ليخ بوزنان', 'ليفركوزن', '2099-06-01 19:30Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002', true, null),
  ('c1950000-0000-4000-8000-0000000000e0', 'ليخ بوزنان', 'ليفركوزن', '2099-06-02 08:00Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002', false, null),
  ('c1950000-0000-4000-8000-000000000010', 'سلتيك', 'بنفيكا', '2099-06-01 19:00Z',
   null, null, false, null);
alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8195-000000000001', 'r195@t.io', now()),
  ('00000000-0000-4000-8195-000000000002', 'r195b@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8195-000000000001', 'r195@t.io', 'R195', '2099-05-01'),
  ('00000000-0000-4000-8195-000000000002', 'r195b@t.io', 'R195b', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1950000-0000-4000-8000-0000000001a1', 'c1950000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8195-000000000001', '2099-06-01'),
  ('c1950000-0000-4000-8000-0000000001a2', 'c1950000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8195-000000000002', '2099-06-01');
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  ('c1950000-0000-4000-8000-00000000b001', 'c1950000-0000-4000-8000-0000000000d0',
   'c1950000-0000-4000-8000-0000000001a1', 1, 2, true, now()),
  ('c1950000-0000-4000-8000-00000000b002', 'c1950000-0000-4000-8000-0000000000d0',
   'c1950000-0000-4000-8000-0000000001a2', 0, 2, false, now()),
  ('c1950000-0000-4000-8000-00000000b003', 'c1950000-0000-4000-8000-0000000000a0',
   'c1950000-0000-4000-8000-0000000001a2', 1, 1, false, now());
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
values ('c1950000-0000-4000-8000-0000000000a0', 1, 2, now());
insert into football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id)
values ('highlightly', 'uel-195', 'fixture', 'c1950000-0000-4000-8000-0000000000a0');
-- M was merged into K before (written as the merge writes it).
insert into competition.fixture_merges (duplicate_fixture_id, kept_fixture_id, merged_by)
values ('c1950000-0000-4000-8000-0000000000c0', 'c1950000-0000-4000-8000-0000000000a0',
        '00000000-0000-4000-8195-000000000001');

do $$
declare
  ids text[];
  r record;
begin
  select array_agg(c.fixture_id order by ord) into ids
    from (select f.*, row_number() over () as ord
            from pg_temp.copies('c1950000-0000-4000-8000-0000000000d0') f) c;
  perform pg_temp.check(
    ids = array['c1950000-0000-4000-8000-0000000000d0',
                'c1950000-0000-4000-8000-0000000000a0',
                'c1950000-0000-4000-8000-0000000000b0'],
    'the copy first, then the kept and the hidden copies by kickoff; not the merged, the test, the far or other clubs');

  select * into r from pg_temp.copies('c1950000-0000-4000-8000-0000000000d0') f
   where f.is_self;
  perform pg_temp.check(r.predictions = 2 and r.doubles = 1 and not r.has_result
                          and not r.linked and not r.hidden,
    'the copy''s own counts');

  select * into r from pg_temp.copies('c1950000-0000-4000-8000-0000000000d0') f
   where f.fixture_id = 'c1950000-0000-4000-8000-0000000000a0';
  perform pg_temp.check(r.predictions = 1 and r.doubles = 0 and r.has_result
                          and r.linked and not r.is_self,
    'the kept copy''s counts, result and link');

  perform pg_temp.check(
    (select count(*) from pg_temp.copies('c1950000-0000-4000-8000-0000000000f0')) = 1,
    'a test fixture has only itself');
  perform pg_temp.check(
    (select count(*) from pg_temp.copies('c1950000-0000-4000-8000-0000000000ff')) = 0,
    'a fixture with no schedule has nothing');
end $$;

rollback;
