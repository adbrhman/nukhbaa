-- End-to-end test for migration 0083: one double per participant per Riyadh
-- kickoff day. A match at 00:30 Riyadh belongs to that day, not to the UTC
-- day it starts in. Rolled back at the end.
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

create function pg_temp.double(id uuid, fixture uuid) returns text
language sql as $$
  select pg_temp.refusal(format(
    'insert into prediction.fixture_predictions
       (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
     values (%L, %L, %L, 1, 0, true, now())',
    id, fixture, 'c8300000-0000-4000-8000-0000000000a1'))
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c8300000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c8300000-0000-4000-8000-000000000010', 'c8300000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- Far in the future, so the kickoff trigger never refuses these writes.
-- f1 21:00 Riyadh 1 June; f2 00:30 Riyadh 2 June (21:30Z on 1 June);
-- f3 22:00 Riyadh 2 June (19:00Z on 2 June).
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8300000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c8300000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 21:30Z'),
  ('c8300000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-02 19:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8300000-0000-4000-8000-000000000010', 'c8300000-0000-4000-8000-0000000000f1', 0),
  ('c8300000-0000-4000-8000-000000000010', 'c8300000-0000-4000-8000-0000000000f2', 1),
  ('c8300000-0000-4000-8000-000000000010', 'c8300000-0000-4000-8000-0000000000f3', 2);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8083-000000000001', 'r1@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8083-000000000001', 'r1@t.io', 'R1', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c8300000-0000-4000-8000-0000000000a1', 'c8300000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8083-000000000001', '2099-06-01');

do $$
begin
  perform pg_temp.check(
    pg_temp.double('c8300000-0000-4000-8000-00000000b001', 'c8300000-0000-4000-8000-0000000000f1') = 'none',
    'a double at 21:00 Riyadh on 1 June is accepted');

  perform pg_temp.check(
    pg_temp.double('c8300000-0000-4000-8000-00000000b002', 'c8300000-0000-4000-8000-0000000000f2') = 'none',
    'a double at 00:30 Riyadh on 2 June is accepted: same UTC day, next Riyadh day');

  perform pg_temp.check(
    pg_temp.double('c8300000-0000-4000-8000-00000000b003', 'c8300000-0000-4000-8000-0000000000f3')
      = '23514/fixture_predictions_one_double_per_day',
    'a second double on 2 June Riyadh is refused, though it is another UTC day');
end $$;

rollback;
