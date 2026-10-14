-- End-to-end test of PostgresSameMatchFinder._sameMatchSql (parameters
-- inlined as function arguments; keep the body identical to the adapter's
-- constant): an admin cannot add a match already on the schedule -- added
-- by the fixtures sync or by hand -- under the same two sides within the
-- window, whichever catalog row of a club either one picked. Batch 138:
-- the Europa League evening of 2026-10-15 was added twice. No migration:
-- the query reads 0012, 0024 and 0098 columns.
\set ON_ERROR_STOP on
begin;

-- PostgresSameMatchFinder._sameMatchSql
create function pg_temp.same_match(
  p_home_id uuid, p_away_id uuid, p_home_name text, p_away_name text,
  p_from timestamptz, p_to timestamptz)
returns table (fixture_id text, home_team text, away_team text, kickoff_at timestamptz)
language sql as $q$
WITH target AS (
  SELECT regexp_replace(translate(btrim(p_home_name), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(p_away_name), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a,
         p_home_id AS home_id,
         p_away_id AS away_id,
         p_from + (p_to - p_from) / 2 AS kickoff
),
candidates AS (
  SELECT s.fixture_id,
         s.home_team,
         s.away_team,
         s.kickoff_at,
         s.home_team_id,
         s.away_team_id,
         regexp_replace(translate(btrim(s.home_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(s.away_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
  FROM competition.fixture_schedules s
  WHERE s.kickoff_at >= p_from
    AND s.kickoff_at < p_to
    -- A test fixture is never a real match, and a hidden one was taken
    -- out of the contest by an admin (0098).
    AND NOT s.is_test
    AND s.hidden_at IS NULL
)
SELECT c.fixture_id::text AS fixture_id,
       c.home_team,
       c.away_team,
       c.kickoff_at
FROM candidates c, target t
-- A side agrees when it is the same catalog team, or the same name once
-- spelling is normalised (one club, two catalog rows), or -- only when a
-- side has no team on file -- one name inside the other, three letters
-- at least. Two different teams on file never agree by a name that sits
-- inside another (audit C-04).
WHERE ((c.home_team_id IS NOT NULL AND c.home_team_id = t.home_id)
       OR c.h = t.h
       OR ((c.home_team_id IS NULL OR t.home_id IS NULL)
           AND length(t.h) >= 3 AND length(c.h) >= 3
           AND (strpos(t.h, c.h) > 0 OR strpos(c.h, t.h) > 0)))
  AND ((c.away_team_id IS NOT NULL AND c.away_team_id = t.away_id)
       OR c.a = t.a
       OR ((c.away_team_id IS NULL OR t.away_id IS NULL)
           AND length(t.a) >= 3 AND length(c.a) >= 3
           AND (strpos(t.a, c.a) > 0 OR strpos(c.a, t.a) > 0)))
ORDER BY abs(extract(epoch from (c.kickoff_at - t.kickoff))),
         c.fixture_id
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

insert into football_data.teams (id, name) values
  ('00000000-0138-4000-8000-000000000001', 'ليون'),
  ('00000000-0138-4000-8000-000000000002', 'ليون'),
  ('00000000-0138-4000-8000-000000000003', 'كريستال بالاس'),
  ('00000000-0138-4000-8000-000000000004', 'باير ليفركوزن'),
  ('00000000-0138-4000-8000-000000000005', 'الأهلي'),
  ('00000000-0138-4000-8000-000000000006', 'الأهلي المصري'),
  ('00000000-0138-4000-8000-000000000007', 'الترجي');

do $$
declare
  lyon_a uuid := '00000000-0138-4000-8000-000000000001';
  lyon_b uuid := '00000000-0138-4000-8000-000000000002';
  palace uuid := '00000000-0138-4000-8000-000000000003';
  leverkusen uuid := '00000000-0138-4000-8000-000000000004';
  ahli uuid := '00000000-0138-4000-8000-000000000005';
  ahly uuid := '00000000-0138-4000-8000-000000000006';
  taraji uuid := '00000000-0138-4000-8000-000000000007';
  synced uuid := '00000000-0138-4000-8000-000000000101';
  card uuid := '00000000-0138-4000-8000-000000000102';
  k timestamptz := '2026-10-15 16:45:00+00';
  w interval := interval '12 hours';
  hit text;
begin
  -- The sync added Lyon - Crystal Palace under its own Lyon row and
  -- linked it to the provider match.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (synced, 'ليون', 'كريستال بالاس', k, lyon_b, palace);
  insert into football_data.external_identity_map
    (external_source, external_id, canonical_table, canonical_id)
  values ('highlightly', 'm-lyon-palace', 'fixture', synced);

  -- 1. The same teams picked: refused, linked or not.
  hit := (select m.fixture_id from pg_temp.same_match(lyon_b, palace, 'ليون', 'كريستال بالاس', k - w, k + w) m);
  perform pg_temp.check(hit = synced::text, 'the same two teams are the same match');

  -- 2. The other Lyon row picked: the same name is the same club.
  hit := (select m.fixture_id from pg_temp.same_match(lyon_a, palace, 'ليون', 'كريستال بالاس', k - w, k + w) m);
  perform pg_temp.check(hit = synced::text, 'another catalog row of the same name is the same club');

  -- 3. Typed by hand, no team found, another spelling.
  hit := (select m.fixture_id from pg_temp.same_match(null, null, 'ليون ', 'كريستال  بالاس', k - w, k + w) m);
  perform pg_temp.check(hit = synced::text, 'hand-typed names that agree are the same match');

  -- 4. A different opponent is a different match.
  hit := (select m.fixture_id from pg_temp.same_match(lyon_a, leverkusen, 'ليون', 'باير ليفركوزن', k - w, k + w) m);
  perform pg_temp.check(hit is null, 'one side alike, the other a different club');

  -- 5. Beyond the window is another match.
  hit := (select m.fixture_id from pg_temp.same_match(lyon_a, palace, 'ليون', 'كريستال بالاس',
                            k + interval '13 hours' - w, k + interval '13 hours' + w) m);
  perform pg_temp.check(hit is null, 'thirteen hours away is another match');

  -- 6. A hidden copy is out of the contest: adding it again is allowed.
  update competition.fixture_schedules set hidden_at = now() where fixture_id = synced;
  hit := (select m.fixture_id from pg_temp.same_match(lyon_a, palace, 'ليون', 'كريستال بالاس', k - w, k + w) m);
  perform pg_temp.check(hit is null, 'a hidden fixture is not in the way');
  update competition.fixture_schedules set hidden_at = null where fixture_id = synced;

  -- 7. A test fixture is never the real match.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test)
  values (card, 'باير ليفركوزن', 'الترجي', k, leverkusen, taraji, true);
  hit := (select m.fixture_id from pg_temp.same_match(leverkusen, taraji, 'باير ليفركوزن', 'الترجي', k - w, k + w) m);
  perform pg_temp.check(hit is null, 'a test fixture is not in the way');
  delete from competition.fixture_schedules where fixture_id = card;

  -- 8. Audit C-04: two different teams on file never agree because one
  --    name sits inside the other.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (card, 'الأهلي المصري', 'الترجي', k, ahly, taraji);
  hit := (select m.fixture_id from pg_temp.same_match(ahli, taraji, 'الأهلي', 'الترجي', k - w, k + w) m);
  perform pg_temp.check(hit is null, 'Al Ahli is not Al Ahly (Egypt)');

  -- 9. ...but a side typed by hand with no team may be the shorter name.
  hit := (select m.fixture_id from pg_temp.same_match(null, taraji, 'الأهلي', 'الترجي', k - w, k + w) m);
  perform pg_temp.check(hit = card::text, 'a hand-typed shorter name agrees');
  delete from competition.fixture_schedules where fixture_id = card;

  -- 10. Of two copies, the nearer kickoff is named.
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
  values (card, 'ليون', 'كريستال بالاس', k + interval '3 hours', lyon_a, palace);
  hit := (select m.fixture_id from pg_temp.same_match(lyon_a, palace, 'ليون', 'كريستال بالاس',
                            k + interval '3 hours' - w, k + interval '3 hours' + w) m);
  perform pg_temp.check(hit = card::text, 'the nearest kickoff is named');
end $$;

rollback;
