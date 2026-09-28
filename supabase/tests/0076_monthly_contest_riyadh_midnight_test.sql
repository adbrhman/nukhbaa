-- End-to-end test for migration 0076: a monthly contest turns over at 00:00
-- Riyadh (21:00 UTC the evening before). Rolled back at the end.
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

insert into competition.competitions (id, name, format, visibility) values
  ('c7600000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public'),
  ('c7600000-0000-4000-8000-000000000002', 'League', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7600000-0000-4000-8000-000000000008', 'c7600000-0000-4000-8000-000000000001', '08/2026', '2026-08-01 00:00Z', '2026-09-01 00:00Z'),
  ('c7600000-0000-4000-8000-000000000009', 'c7600000-0000-4000-8000-000000000001', '09/2026', '2026-09-01 00:00Z', '2026-10-01 00:00Z'),
  ('c7600000-0000-4000-8000-000000000010', 'c7600000-0000-4000-8000-000000000001', '10/2026', '2026-10-01 00:00Z', '2026-11-01 00:00Z'),
  ('c7600000-0000-4000-8000-000000000020', 'c7600000-0000-4000-8000-000000000002', '2026/27', '2026-08-01 00:00Z', '2027-06-01 00:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c7600000-0000-4000-8000-0000000000f1', 'Home', 'Away', '2026-09-30 19:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c7600000-0000-4000-8000-000000000009', 'c7600000-0000-4000-8000-0000000000f1', 0);

do $$
declare
  moved integer;
begin
  moved := competition.align_monthly_seasons_to_riyadh('2026-09-28 12:00Z');
  perform pg_temp.check(moved = 3, 'moves the running month''s end and the next month''s start and end');

  perform pg_temp.check(
    (select end_at from competition.seasons where label = '09/2026') = '2026-10-01 00:00+03',
    'September ends at midnight Riyadh');
  perform pg_temp.check(
    (select start_at from competition.seasons where label = '09/2026') = '2026-09-01 00:00Z',
    'a month already running keeps its start');
  perform pg_temp.check(
    (select start_at from competition.seasons where label = '10/2026') = '2026-10-01 00:00+03',
    'October starts at midnight Riyadh');
  perform pg_temp.check(
    (select end_at from competition.seasons where label = '10/2026') = '2026-11-01 00:00+03',
    'October ends at midnight Riyadh');
  perform pg_temp.check(
    (select end_at from competition.seasons where label = '08/2026') = '2026-09-01 00:00Z',
    'a finished month is not touched');
  perform pg_temp.check(
    (select start_at from competition.seasons where label = '2026/27') = '2026-08-01 00:00Z',
    'a league edition is not a monthly contest');

  -- The current season at 00:30 Riyadh on 1 October is October.
  perform pg_temp.check(
    (select label from competition.seasons
      where competition_id = 'c7600000-0000-4000-8000-000000000001'
        and start_at <= '2026-10-01 00:30+03' and end_at > '2026-10-01 00:30+03') = '10/2026',
    'October is current half an hour after midnight Riyadh');
  perform pg_temp.check(
    (select label from competition.seasons
      where competition_id = 'c7600000-0000-4000-8000-000000000001'
        and start_at <= '2026-09-30 23:30+03' and end_at > '2026-09-30 23:30+03') = '09/2026',
    'September is current half an hour before midnight Riyadh');

  perform pg_temp.check(
    competition.align_monthly_seasons_to_riyadh('2026-09-28 12:00Z') = 0,
    'a second run changes nothing');
end $$;

-- A fixture that would leave its month blocks the whole move.
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7600000-0000-4000-8000-000000000011', 'c7600000-0000-4000-8000-000000000001', '11/2026', '2026-11-01 00:00+03', '2026-12-01 00:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c7600000-0000-4000-8000-0000000000f2', 'Late', 'Kick', '2026-11-30 22:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c7600000-0000-4000-8000-000000000011', 'c7600000-0000-4000-8000-0000000000f2', 0);

do $$
declare
  refused boolean := false;
begin
  begin
    perform competition.align_monthly_seasons_to_riyadh('2026-09-28 12:00Z');
  exception when others then
    refused := true;
  end;
  perform pg_temp.check(refused, 'refuses to strand a linked late fixture');
  perform pg_temp.check(
    (select end_at from competition.seasons where label = '11/2026') = '2026-12-01 00:00Z',
    'nothing moved when refused');
end $$;

rollback;
