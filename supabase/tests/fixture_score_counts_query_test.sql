-- Test for PostgresFixtureScoreCounter.countSql (batch 156): the scores of
-- each named fixture are counted in one statement, a fixture with none is
-- absent, and a fixture not named is not counted. Keep the body identical
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

-- PostgresFixtureScoreCounter.countSql
create function pg_temp.counts(p_fixture_ids uuid[])
returns table (fixture_id text, scores int)
language sql as $q$
SELECT fixture_id::text AS fixture_id, count(*)::int AS scores
FROM scoring.fixture_scores
WHERE fixture_id = ANY(p_fixture_ids::uuid[])
GROUP BY fixture_id
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0156-4000-8000-000000000001', 'c1@t.io', now()),
  ('00000000-0156-4000-8000-000000000002', 'c2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0156-4000-8000-000000000001', 'c1@t.io', 'One'),
  ('00000000-0156-4000-8000-000000000002', 'c2@t.io', 'Two');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0156-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0156-4000-8000-0000000000e1', '00000000-0156-4000-8000-0000000000c1',
        '08/2099', '2099-08-01', '2099-09-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0156-4000-8000-0000000000a1', '00000000-0156-4000-8000-0000000000e1',
   '00000000-0156-4000-8000-000000000001', '2099-08-01'),
  ('00000000-0156-4000-8000-0000000000a2', '00000000-0156-4000-8000-0000000000e1',
   '00000000-0156-4000-8000-000000000002', '2099-08-01');

-- f1: both scored; f2: one; f3: none; f4: scored but not asked for.
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('00000000-0156-4000-8000-0000000000f1', '00000000-0156-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('00000000-0156-4000-8000-0000000000f1', '00000000-0156-4000-8000-0000000000a2', 1, 'incorrect', 0),
  ('00000000-0156-4000-8000-0000000000f2', '00000000-0156-4000-8000-0000000000a1', 1, 'correct_outcome', 1),
  ('00000000-0156-4000-8000-0000000000f4', '00000000-0156-4000-8000-0000000000a1', 1, 'incorrect', 0);

do $$
declare
  asked uuid[] := array[
    '00000000-0156-4000-8000-0000000000f1',
    '00000000-0156-4000-8000-0000000000f2',
    '00000000-0156-4000-8000-0000000000f3']::uuid[];
begin
  perform pg_temp.check(
    (select scores from pg_temp.counts(asked)
      where fixture_id = '00000000-0156-4000-8000-0000000000f1') = 2,
    'both players of f1');
  perform pg_temp.check(
    (select scores from pg_temp.counts(asked)
      where fixture_id = '00000000-0156-4000-8000-0000000000f2') = 1,
    'one player of f2');
  perform pg_temp.check(
    not exists (select 1 from pg_temp.counts(asked)
                 where fixture_id = '00000000-0156-4000-8000-0000000000f3'),
    'a fixture with no score is absent');
  perform pg_temp.check(
    not exists (select 1 from pg_temp.counts(asked)
                 where fixture_id = '00000000-0156-4000-8000-0000000000f4'),
    'a fixture not asked for is not counted');
  perform pg_temp.check(
    (select count(*) from pg_temp.counts(array[]::uuid[])) = 0,
    'nothing asked, nothing counted');
end $$;

rollback;
