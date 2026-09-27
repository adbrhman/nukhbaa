-- End-to-end test for migration 0072: the streak bonus stays in the ledger
-- but leaves leaderboard.season_fixture_standings (month arrows, personal
-- record). Rolled back at the end.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8072-0000000000a1', 'a72@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0000-4000-8072-0000000000a1', 'a72@t.io', 'A72');
insert into competition.competitions (id, name, format, visibility)
values ('c7200000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c7200000-0000-4000-8000-000000000010', 'c7200000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01');
insert into competition.participants (id, season_id, user_id, joined_at)
values ('c7200000-0000-4000-8000-0000000000a1', 'c7200000-0000-4000-8000-000000000010', '00000000-0000-4000-8072-0000000000a1', '2026-10-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
values ('c7200000-0000-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2026-10-05 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
values ('c7200000-0000-4000-8000-000000000010', 'c7200000-0000-4000-8000-0000000000f1', 0);
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points)
values ('c7200000-0000-4000-8000-0000000000f1', 'c7200000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3);
insert into ledger.fixture_point_entries (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
values (gen_random_uuid(), 'c7200000-0000-4000-8000-0000000000a1', 'c7200000-0000-4000-8000-0000000000f1', 'streak_bonus', 2, 'streak:3', now());

do $$
begin
  if (select total_points from leaderboard.season_fixture_standings
       where participant_id = 'c7200000-0000-4000-8000-0000000000a1') <> 3 then
    raise exception 'FAILED: the monthly standings must not include the streak bonus';
  end if;
  raise notice 'ok - the monthly standings read 3 (the bonus of 2 is not added)';
  if (select count(*) from ledger.fixture_point_entries
       where participant_id = 'c7200000-0000-4000-8000-0000000000a1'
         and entry_kind = 'streak_bonus') <> 1 then
    raise exception 'FAILED: the streak bonus entry must stay in the ledger';
  end if;
  raise notice 'ok - the streak bonus entry is still in the ledger';
end $$;

rollback;
