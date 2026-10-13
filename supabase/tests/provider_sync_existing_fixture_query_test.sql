-- End-to-end test of PostgresProviderSyncStore._existingSql (parameters
-- inlined as function arguments; keep the body identical to the adapter's
-- constant): the fixtures sync adopts a hand-added fixture only when both
-- sides agree -- by the team on file, or, for a side typed by hand, by its
-- normalised name -- and never a fixture already linked to a provider
-- match. Audit C-04: Al Ahli (Saudi) took a hand-added Al Ahly (Egypt)
-- card, and Inter could take Milan's. No migration: the query reads 0012,
-- 0013, 0024 and 0098 tables.
\set ON_ERROR_STOP on
begin;

-- PostgresProviderSyncStore._existingSql
create function pg_temp.existing_fixture(
  p_home_id uuid, p_away_id uuid, p_home_name text, p_away_name text,
  p_kickoff timestamptz, p_from timestamptz, p_to timestamptz)
returns text
language sql as $q$
WITH target AS (
  SELECT regexp_replace(translate(btrim(p_home_name), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(p_away_name), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
),
candidates AS (
  SELECT s.fixture_id,
         s.kickoff_at,
         s.home_team_id,
         s.away_team_id,
         regexp_replace(translate(btrim(s.home_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(s.away_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
  FROM competition.fixture_schedules s
  WHERE s.kickoff_at >= p_from
    AND s.kickoff_at < p_to
    -- A test fixture is never the real match a provider reports (0098).
    AND NOT s.is_test
    -- A fixture already linked to a provider match is that match, never
    -- this one (audit C-04: a second link let one result land on both).
    AND NOT EXISTS (
      SELECT 1
      FROM football_data.external_identity_map m
      WHERE m.canonical_table = 'fixture'
        AND m.canonical_id = s.fixture_id
    )
),
sides AS (
  SELECT c.fixture_id,
         c.kickoff_at,
         COALESCE(c.home_team_id = p_home_id, false) AS home_id_same,
         COALESCE(c.away_team_id = p_away_id, false) AS away_id_same,
         c.home_team_id IS NULL AS home_untyped,
         c.away_team_id IS NULL AS away_untyped,
         -- A side with a team on file is that team and no other, whatever
         -- its name says (audit C-04: a name can sit inside another club name).
         -- Only a side without one is matched by its normalised name:
         -- equal, or one inside the other, three letters at least.
         CASE
           WHEN c.home_team_id IS NOT NULL THEN c.home_team_id = p_home_id
           ELSE c.h = t.h
             OR (length(t.h) >= 3 AND length(c.h) >= 3
                 AND (strpos(t.h, c.h) > 0 OR strpos(c.h, t.h) > 0))
         END AS home_same,
         CASE
           WHEN c.away_team_id IS NOT NULL THEN c.away_team_id = p_away_id
           ELSE c.a = t.a
             OR (length(t.a) >= 3 AND length(c.a) >= 3
                 AND (strpos(t.a, c.a) > 0 OR strpos(c.a, t.a) > 0))
         END AS away_same,
         abs(extract(epoch from (c.kickoff_at - p_kickoff))) AS gap
  FROM candidates c, target t
)
SELECT s.fixture_id::text AS fixture_id
FROM sides s
WHERE (s.home_same AND s.away_same)
   -- One side certain by its team, the other typed by hand with no team
   -- on file under a name the catalog does not use, within three hours.
   OR (s.gap <= 10800
       AND ((s.home_id_same AND s.away_untyped)
         OR (s.away_id_same AND s.home_untyped)))
ORDER BY (s.home_id_same AND s.away_id_same) DESC,
         (s.home_same AND s.away_same) DESC,
         s.gap,
         s.fixture_id
LIMIT 1
$q$;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- Catalog: two clubs whose names sit inside each other after
-- normalisation, and their opponents.
insert into football_data.teams (id, name) values
  ('00000000-0c04-4000-8000-000000000001', 'الأهلي'),
  ('00000000-0c04-4000-8000-000000000002', 'الأهلي المصري'),
  ('00000000-0c04-4000-8000-000000000003', 'الفيحاء'),
  ('00000000-0c04-4000-8000-000000000004', 'الترجي'),
  ('00000000-0c04-4000-8000-000000000005', 'ميلان'),
  ('00000000-0c04-4000-8000-000000000006', 'إنتر ميلان'),
  ('00000000-0c04-4000-8000-000000000007', 'كومو'),
  ('00000000-0c04-4000-8000-000000000008', 'لاتسيو');

do $$
declare
  ahli uuid := '00000000-0c04-4000-8000-000000000001';
  ahly uuid := '00000000-0c04-4000-8000-000000000002';
  fayha uuid := '00000000-0c04-4000-8000-000000000003';
  taraji uuid := '00000000-0c04-4000-8000-000000000004';
  milan uuid := '00000000-0c04-4000-8000-000000000005';
  inter uuid := '00000000-0c04-4000-8000-000000000006';
  como uuid := '00000000-0c04-4000-8000-000000000007';
  lazio uuid := '00000000-0c04-4000-8000-000000000008';
  egypt_card uuid := '00000000-0c04-4000-8000-000000000101';
  milan_card uuid := '00000000-0c04-4000-8000-000000000102';
  k timestamptz := '2026-11-06 18:00:00+00';
  w interval := interval '12 hours';
  hit text;
begin
  -- 1. A hand-added Al Ahly (Egypt) card at 16:00 is not the Saudi Al
  --    Ahli match at 18:00: the team on file decides, not the name.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (egypt_card, 'الأهلي المصري', 'الترجي', k - interval '2 hours', ahly, taraji);
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit is null, 'another club with a name inside it is never adopted');

  -- 2. The same card typed by hand, no team on file: the other side
  --    still has to agree.
  update competition.fixture_schedules
     set home_team_id = null, away_team_id = null
   where fixture_id = egypt_card;
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit is null, 'one name inside another is not enough');
  delete from competition.fixture_schedules where fixture_id = egypt_card;

  -- 3. Milan away at 16:00, already linked to its provider match; Inter
  --    away at 18:45 must not take it.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (milan_card, 'كومو', 'ميلان', k - interval '2 hours', como, milan);
  insert into football_data.external_identity_map
    (external_source, external_id, canonical_table, canonical_id)
  values ('football-data', 'm-milan', 'fixture', milan_card);
  hit := pg_temp.existing_fixture(lazio, inter, 'لاتسيو', 'إنتر ميلان',
                                  k + interval '45 minutes', k - w, k + w);
  perform pg_temp.check(hit is null, 'Inter never takes the Milan card');
  hit := pg_temp.existing_fixture(como, milan, 'كومو', 'ميلان',
                                  k - interval '2 hours', k - w, k + w);
  perform pg_temp.check(hit is null, 'a card linked already is never linked twice');
  delete from football_data.external_identity_map where canonical_id = milan_card;
  delete from competition.fixture_schedules where fixture_id = milan_card;
end $$;

do $$
declare
  ahli uuid := '00000000-0c04-4000-8000-000000000001';
  fayha uuid := '00000000-0c04-4000-8000-000000000003';
  by_ids uuid := '00000000-0c04-4000-8000-000000000201';
  by_names uuid := '00000000-0c04-4000-8000-000000000202';
  one_side uuid := '00000000-0c04-4000-8000-000000000203';
  k timestamptz := '2026-11-06 18:00:00+00';
  w interval := interval '12 hours';
  hit text;
begin
  -- 4. The same match added by hand with its teams picked: adopted.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (by_ids, 'الأهلي', 'الفيحاء', k + interval '1 hour', ahli, fayha);
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit = by_ids::text, 'the same two teams on file are adopted');
  delete from competition.fixture_schedules where fixture_id = by_ids;

  -- 5. Typed by hand, no teams on file, other spelling: adopted.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
  values (by_names, 'الاهلى', 'الفيحاء', k);
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit = by_names::text, 'hand-typed names that agree are adopted');

  -- 6. Both present: the card with the teams on file wins, though further.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (by_ids, 'الأهلي', 'الفيحاء', k + interval '2 hours', ahli, fayha);
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit = by_ids::text, 'the teams on file beat a closer name match');
  delete from competition.fixture_schedules where fixture_id in (by_ids, by_names);

  -- 7. One side picked, the other typed under a name the catalog does
  --    not use: adopted within three hours, not beyond.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id)
  values (one_side, 'الأهلي', 'Al Fayha', k + interval '2 hours', ahli);
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit = one_side::text, 'one team on file and a free-typed other side, within 3 h');
  update competition.fixture_schedules
     set kickoff_at = k + interval '4 hours' where fixture_id = one_side;
  hit := pg_temp.existing_fixture(ahli, fayha, 'الأهلي', 'الفيحاء', k, k - w, k + w);
  perform pg_temp.check(hit is null, 'but not four hours away');
  delete from competition.fixture_schedules where fixture_id = one_side;
end $$;

rollback;
