-- End-to-end test for migration 0193 (script 190): the statements
-- PostgresDailySelectionLog runs keep one row per Riyadh day and one per
-- match it looked at; every run of a day replaces that day's rows; a score
-- left out is null; a mode other than shadow or on is refused.
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

-- PostgresDailySelectionLog._daySql, _clearSql and _candidatesSql with
-- their parameters inlined, in the transaction's order.
create function pg_temp.record(
  p_day date, p_mode text, p_base int, p_target int, p_busy boolean,
  p_chosen int, p_final int, p_note text, p_at timestamptz,
  p_sources text[], p_ids text[], p_leagues text[], p_homes text[],
  p_aways text[], p_kickoffs text[], p_scores text[], p_reasons text[],
  p_decisions text[]
) returns void
language plpgsql as $$
begin
  INSERT INTO football_data.daily_selection_days
    (riyadh_day, mode, base_count, target, busy, chosen, final_count, note,
     updated_at)
  VALUES (p_day, p_mode, p_base, p_target, p_busy, p_chosen, p_final, p_note,
          p_at)
  ON CONFLICT (riyadh_day) DO UPDATE
  SET mode = EXCLUDED.mode,
      base_count = EXCLUDED.base_count,
      target = EXCLUDED.target,
      busy = EXCLUDED.busy,
      chosen = EXCLUDED.chosen,
      final_count = EXCLUDED.final_count,
      note = EXCLUDED.note,
      updated_at = EXCLUDED.updated_at;

  DELETE FROM football_data.daily_selection_candidates
  WHERE riyadh_day = p_day;

  INSERT INTO football_data.daily_selection_candidates
    (riyadh_day, source, external_id, league_name, home_team, away_team,
     kickoff_at, score, reasons, decision)
  SELECT p_day, c.source, c.external_id, c.league_name, c.home_team,
         c.away_team, c.kickoff_at::timestamptz,
         nullif(c.score, '')::integer, c.reasons, c.decision
  FROM unnest(p_sources, p_ids, p_leagues, p_homes, p_aways, p_kickoffs,
              p_scores, p_reasons, p_decisions)
    AS c(source, external_id, league_name, home_team, away_team, kickoff_at,
         score, reasons, decision)
  ON CONFLICT (riyadh_day, source, external_id) DO NOTHING;
end $$;

do $$
declare
  saturday date := '2030-01-12';
  refused boolean;
begin
  perform pg_temp.record(saturday, 'shadow', 4, 20, true, 2, 6, '',
    '2030-01-10 21:05+00',
    array['football-data', 'highlightly', 'football-data'],
    array['m1', 'm2', 'm3'],
    array['الدوري الإسباني', 'دوري روشن السعودي', 'الدوري الإسباني'],
    array['ريال مدريد', 'الهلال', 'خيتافي'],
    array['برشلونة', 'النصر', 'قادش'],
    array['2030-01-12T20:00:00.000Z', '2030-01-12T17:00:00.000Z',
          '2030-01-12T13:00:00.000Z'],
    array['58', '58', ''],
    array['المضيف 1/20: 25', 'المضيف 1/18: 25', ''],
    array['تُختار', 'تُختار', 'نادٍ غير مربوط']);
  perform pg_temp.check(
    (select count(*) from football_data.daily_selection_candidates
      where riyadh_day = saturday) = 3,
    'every match looked at is kept');
  perform pg_temp.check(
    (select score from football_data.daily_selection_candidates
      where external_id = 'm3') is null,
    'a match that could not be chosen has no score');

  -- The 12:05 run of the same day replaces the 00:05 one.
  perform pg_temp.record(saturday, 'shadow', 4, 20, true, 1, 5, 'x',
    '2030-01-11 09:05+00',
    array['football-data'], array['m1'], array['الدوري الإسباني'],
    array['ريال مدريد'], array['برشلونة'],
    array['2030-01-12T20:00:00.000Z'], array['58'], array[''],
    array['تُختار']);
  perform pg_temp.check(
    (select final_count from football_data.daily_selection_days
      where riyadh_day = saturday) = 5,
    'the day row holds the last run');
  perform pg_temp.check(
    (select count(*) from football_data.daily_selection_candidates
      where riyadh_day = saturday) = 1,
    'the matches of the last run alone are kept');

  begin
    perform pg_temp.record('2030-01-13', 'off', 0, 15, false, 0, 0, '',
      now(), array[]::text[], array[]::text[], array[]::text[],
      array[]::text[], array[]::text[], array[]::text[], array[]::text[],
      array[]::text[], array[]::text[]);
    refused := false;
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'a mode other than shadow or on is refused');

  perform pg_temp.check(
    (select bool_and(relrowsecurity) from pg_class
      where oid in ('football_data.daily_selection_days'::regclass,
                    'football_data.daily_selection_candidates'::regclass)),
    'row level security is on');
end $$;

rollback;
