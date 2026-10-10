-- End-to-end test for migration 0074: the daily rank snapshot breaks a
-- points tie by the month's invitation points, then by exact scorelines.
-- Rolled back at the end.
\set ON_ERROR_STOP on
begin;

-- The fixtures below kick off on fixed dates, while the after-kickoff
-- guard (migration 0019) compares with the real clock: left on, this test
-- would start failing once those dates pass. It is switched off for this
-- rolled-back transaction only (the guard itself is unchanged).
--
-- For the same reason every score carries a fixed scored_at: the sweep only
-- pays for a prediction graded by its p_now, and the column's default (the
-- real clock) passed the test's p_now on 2026-10-10, which made this test
-- fail from that day on.
alter table prediction.fixture_predictions
  disable trigger fixture_predictions_reject_write_after_kickoff;

create function pg_temp.mk_player(n int, points int, exact int) returns uuid
language plpgsql as $$
declare
  u uuid := ('00000000-0000-4000-8074-' || lpad(n::text, 12, '0'))::uuid;
  p uuid := ('c7400000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
  i int;
begin
  insert into auth.users (id, email, email_confirmed_at) values (u, 'p' || n || '@t.io', now());
  insert into identity.users (id, email, display_name, created_at)
  values (u, 'p' || n || '@t.io', 'P' || n, '2026-09-01');
  insert into competition.participants (id, season_id, user_id, joined_at)
  values (p, 'c7400000-0000-4000-8000-000000000010', u, '2026-10-01');
  -- points as exact calls (3 each) plus correct outcomes (0 each here)
  for i in 1..3 loop
    insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
    values (('c7400000-0000-4000-8000-0000000000f' || i)::uuid, p, 1,
            case when i <= exact then 'exact_scoreline' else 'correct_outcome' end,
            case when i = 1 then points else 0 end,
            '2026-10-05 20:00+03');
  end loop;
  return u;
end $$;

insert into competition.competitions (id, name, format, visibility)
values ('c7400000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c7400000-0000-4000-8000-000000000010', 'c7400000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c7400000-0000-4000-8000-0000000000f1', 'A', 'B', '2026-10-05 18:00+03'),
  ('c7400000-0000-4000-8000-0000000000f2', 'C', 'D', '2026-10-05 18:00+03'),
  ('c7400000-0000-4000-8000-0000000000f3', 'E', 'F', '2026-10-05 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c7400000-0000-4000-8000-000000000010', 'c7400000-0000-4000-8000-0000000000f1', 0),
  ('c7400000-0000-4000-8000-000000000010', 'c7400000-0000-4000-8000-0000000000f2', 1),
  ('c7400000-0000-4000-8000-000000000010', 'c7400000-0000-4000-8000-0000000000f3', 2);

do $$
declare
  ahmad uuid; khaled uuid; sami uuid; omar uuid; invitee uuid;
  code text;
  rank_of text;
begin
  -- Ahmad and Khaled: 120 points, one exact call each.
  ahmad  := pg_temp.mk_player(1, 120, 1);
  khaled := pg_temp.mk_player(2, 120, 1);
  -- Sami: 120 points, two exact calls, no invitations.
  sami   := pg_temp.mk_player(3, 120, 2);
  -- Omar: exactly like Khaled.
  omar   := pg_temp.mk_player(4, 120, 1);

  -- Ahmad has one paid invitation in October.
  update gamification.feature_flags set enabled = true where flag_key = 'referrals';
  code := gamification.ensure_referral_code(ahmad);
  insert into auth.users (id, email, email_confirmed_at)
  values ('00000000-0000-4000-8074-000000000099', 'i@t.io', now());
  insert into identity.users (id, email, display_name, created_at)
  values ('00000000-0000-4000-8074-000000000099', 'i@t.io', 'I', '2026-10-02 10:00+03');
  invitee := '00000000-0000-4000-8074-000000000099';
  perform gamification.claim_referral(invitee, code, '5.5.5.5', 'inst-99', '2026-10-02 10:05+03');
  insert into competition.participants (id, season_id, user_id, joined_at)
  values ('c7400000-0000-4000-8000-000000000099', 'c7400000-0000-4000-8000-000000000010', invitee, '2026-10-02');
  insert into prediction.fixture_predictions (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values (gen_random_uuid(), 'c7400000-0000-4000-8000-0000000000f1', 'c7400000-0000-4000-8000-000000000099', 1, 0, false, '2026-10-05 12:00+03');
  insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
  values ('c7400000-0000-4000-8000-0000000000f1', 'c7400000-0000-4000-8000-000000000099', 1, 'incorrect', 0, '2026-10-05 20:00+03');
  perform gamification.qualify_referrals('2026-10-10 12:00+03');

  perform leaderboard.capture_season_rank_snapshots('2026-10-10');
  select string_agg(u.display_name || '=' || s.rank, ' ' order by s.rank, u.display_name)
    into rank_of
    from leaderboard.season_rank_snapshots s
    join competition.participants p on p.id = s.participant_id
    join identity.users u on u.id = p.user_id
   where s.season_id = 'c7400000-0000-4000-8000-000000000010'
     and s.captured_on = '2026-10-10'
     and s.total_points = 120;
  raise notice 'snapshot: %', rank_of;
  if rank_of <> 'P1=1 P3=2 P2=3 P4=3' then
    raise exception 'FAILED: expected P1=1 P3=2 P2=3 P4=3, got %', rank_of;
  end if;
  raise notice 'ok - 120 each: the invitation point puts Ahmad first';
  raise notice 'ok - no invitations: more exact scorelines put Sami second';
  raise notice 'ok - level on all three: Khaled and Omar share third';

  if (select sum(total_points) from leaderboard.season_fixture_standings s
        join competition.participants p on p.id = s.participant_id
       where p.user_id = ahmad) <> 120 then
    raise exception 'FAILED: the invitation point must not add to the points';
  end if;
  raise notice 'ok - Ahmad still has 120 prediction points, not 121';
end $$;

rollback;
