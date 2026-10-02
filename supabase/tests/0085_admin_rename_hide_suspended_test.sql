-- End-to-end test for migration 0085: the rename audit token exists, and a
-- suspended account leaves the live standings view and comes back unchanged
-- when reinstated. Rolled back at the end.
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

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8085-000000000001', 'k1@t.io', now()),
  ('00000000-0000-4000-8085-000000000002', 'k2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0000-4000-8085-000000000001', 'k1@t.io', 'K1'),
  ('00000000-0000-4000-8085-000000000002', 'k2@t.io', 'K2');
insert into competition.competitions (id, name, format, visibility)
values ('c8500000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c8500000-0000-4000-8000-000000000010', 'c8500000-0000-4000-8000-000000000001', '06/2099', '2099-06-01', '2099-07-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c8500000-0000-4000-8000-0000000000a1', 'c8500000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8085-000000000001', '2099-06-01'),
  ('c8500000-0000-4000-8000-0000000000a2', 'c8500000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8085-000000000002', '2099-06-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
values ('c8500000-0000-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2099-06-10 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
values ('c8500000-0000-4000-8000-000000000010', 'c8500000-0000-4000-8000-0000000000f1', 0);
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c8500000-0000-4000-8000-0000000000f1', 'c8500000-0000-4000-8000-0000000000a1', 1, 'correct_outcome', 1),
  ('c8500000-0000-4000-8000-0000000000f1', 'c8500000-0000-4000-8000-0000000000a2', 1, 'exact_scoreline', 3);

do $$
begin
  perform pg_temp.check(
    exists (
      select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'admin' and t.typname = 'audit_action'
         and e.enumlabel = 'user_renamed'),
    'admin.audit_action has user_renamed');
end $$;

update identity.users set status = 'suspended'
 where id = '00000000-0000-4000-8085-000000000002';

do $$
begin
  perform pg_temp.check(
    (select count(*) from leaderboard.season_fixture_standings
      where season_id = 'c8500000-0000-4000-8000-000000000010') = 1
    and (select participant_id from leaderboard.season_fixture_standings
          where season_id = 'c8500000-0000-4000-8000-000000000010')
        = 'c8500000-0000-4000-8000-0000000000a1',
    'a suspended account leaves the standings');
end $$;

update identity.users set status = 'active'
 where id = '00000000-0000-4000-8085-000000000002';

do $$
begin
  perform pg_temp.check(
    (select total_points from leaderboard.season_fixture_standings
      where participant_id = 'c8500000-0000-4000-8000-0000000000a2') = 3,
    'reinstating brings the same points back');
end $$;

rollback;
