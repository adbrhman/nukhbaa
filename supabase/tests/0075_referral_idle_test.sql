-- End-to-end test for migration 0075: an invitee idle for 7 days loses the
-- inviter's point (a compensating event) and is suspended, never deleted;
-- the admin view reports every invitation's state. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

-- The fixtures below kick off on fixed dates, while the after-kickoff
-- guard (migration 0019) compares with the real clock: left on, this test
-- would start failing once those dates pass. It is switched off for this
-- rolled-back transaction only (the guard itself is unchanged).
alter table prediction.fixture_predictions
  disable trigger fixture_predictions_reject_write_after_kickoff;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

create function pg_temp.mk_user(n int, created timestamptz, role text default 'user')
returns uuid language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8075-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, 'i' || n || '@t.io', created);
  insert into identity.users (id, email, display_name, created_at, role)
  values (v, 'i' || n || '@t.io', 'Idle ' || n, created, role::identity.platform_role);
  return v;
end $$;

insert into competition.competitions (id, name, format, visibility)
values ('c7500000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7500000-0000-4000-8000-000000000010', 'c7500000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
select ('c7500000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'H' || n, 'A' || n,
       timestamptz '2026-10-02 18:00+03' + (n - 1) * interval '1 day'
  from generate_series(1, 20) n;
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c7500000-0000-4000-8000-000000000010',
       ('c7500000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, n
  from generate_series(1, 20) n;

-- A prediction by u on fixture n at time t, graded as incorrect.
create function pg_temp.predict(u uuid, n int, t timestamptz) returns void
language plpgsql as $$
declare
  pid uuid;
  f uuid := ('c7500000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid;
begin
  insert into competition.participants (id, season_id, user_id, joined_at)
  values (gen_random_uuid(), 'c7500000-0000-4000-8000-000000000010', u, '2026-10-01')
  on conflict (season_id, user_id) do nothing;
  select id into pid from competition.participants
   where season_id = 'c7500000-0000-4000-8000-000000000010' and user_id = u;
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values (gen_random_uuid(), f, pid, 1, 0, false, t);
  insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
  values (f, pid, 1, 'incorrect', 0, t + interval '6 hours');
end $$;

create function pg_temp.state(u uuid) returns text language sql as $$
  select state from gamification.referral_invitations where invitee_id = u
$$;

do $$
declare
  a uuid; b uuid; c uuid; adm uuid; d uuid; code text;
begin
  a := pg_temp.mk_user(1, '2026-09-01');
  code := gamification.ensure_referral_code(a);
  update gamification.feature_flags set enabled = true where flag_key = 'referrals';

  -- b: plays once on Oct 2, then nothing.
  b := pg_temp.mk_user(2, '2026-10-01 10:00+03');
  perform gamification.claim_referral(b, code, '1.0.0.2', 'inst-b-1', '2026-10-01 10:05+03');
  perform pg_temp.predict(b, 1, '2026-10-02 12:00+03');
  -- c: plays on Oct 2, then again on Oct 8.
  c := pg_temp.mk_user(3, '2026-10-01 11:00+03');
  perform gamification.claim_referral(c, code, '1.0.0.3', 'inst-c-1', '2026-10-01 11:05+03');
  perform pg_temp.predict(c, 1, '2026-10-02 12:00+03');
  -- d: never plays.
  d := pg_temp.mk_user(5, '2026-10-01 12:00+03');
  perform gamification.claim_referral(d, code, '1.0.0.5', 'inst-d-1', '2026-10-01 12:05+03');

  perform gamification.qualify_referrals('2026-10-03 12:00+03');
  perform pg_temp.check(pg_temp.state(b) = 'paid' and pg_temp.state(c) = 'paid', 'both players are paid after their first graded match');
  perform pg_temp.check(pg_temp.state(d) = 'pending', 'an invitee who never played stays pending');

  perform pg_temp.predict(c, 7, '2026-10-08 12:00+03');

  -- Oct 9: six days since the payment -- nobody is idle yet.
  perform gamification.qualify_referrals('2026-10-09 12:00+03');
  perform pg_temp.check(pg_temp.state(b) = 'paid', 'six quiet days are not yet idle');

  -- Oct 11: b has been quiet for 8 days, c played 3 days ago.
  perform gamification.qualify_referrals('2026-10-11 12:00+03');
  perform pg_temp.check(pg_temp.state(b) = 'revoked', 'seven quiet days after the payment revoke the point');
  perform pg_temp.check(
    (select payload ->> 'reason' from gamification.events
      where ref_id = b and event_type = 'referral_revoked') = 'inactive_7_days',
    'the revocation records why');
  perform pg_temp.check((select status::text from identity.users where id = b) = 'suspended', 'the idle account is suspended');
  perform pg_temp.check(exists (select 1 from identity.users where id = b), 'the idle account is not deleted');
  perform pg_temp.check(
    (select count(*) from prediction.fixture_predictions fp
       join competition.participants p on p.id = fp.participant_id
      where p.user_id = b) = 1,
    'its prediction is kept');
  perform pg_temp.check(pg_temp.state(c) = 'paid', 'a player who predicted within the week keeps the point');
  perform pg_temp.check(
    (select referral_points from gamification.referral_month_points
      where user_id = a and label = '10/2026') = 1,
    'the inviter keeps only the active friend''s point');

  -- A repeat writes nothing, and a reinstated account is not suspended again.
  perform pg_temp.check(gamification.qualify_referrals('2026-10-12 12:00+03') = 0, 'a repeat sweep writes nothing');
  update identity.users set status = 'active' where id = b;
  perform gamification.qualify_referrals('2026-10-20 12:00+03');
  perform pg_temp.check((select status::text from identity.users where id = b) = 'active', 'an account an admin reinstated stays active');

  -- c quiet after Oct 8: revoked on Oct 16.
  perform pg_temp.check(pg_temp.state(c) = 'revoked', 'the active friend is revoked too once quiet for a week');

  -- An admin account is revoked but never suspended by the sweep.
  adm := pg_temp.mk_user(4, '2026-10-01 13:00+03', 'admin');
  perform gamification.claim_referral(adm, code, '1.0.0.4', 'inst-adm-1', '2026-10-01 13:05+03');
  perform pg_temp.predict(adm, 2, '2026-10-03 12:00+03');
  perform gamification.qualify_referrals('2026-10-04 12:00+03');
  perform gamification.qualify_referrals('2026-10-12 12:00+03');
  perform pg_temp.check(pg_temp.state(adm) = 'revoked' and (select status::text from identity.users where id = adm) = 'active',
    'an admin account loses the point but is never suspended');

  -- While the switch is off nothing is taken back.
  update gamification.feature_flags set enabled = false where flag_key = 'referrals';
  perform pg_temp.predict(d, 3, '2026-10-04 12:00+03');
  update gamification.feature_flags set enabled = true where flag_key = 'referrals';
  perform gamification.qualify_referrals('2026-10-05 12:00+03');
  update gamification.feature_flags set enabled = false where flag_key = 'referrals';
  perform pg_temp.check(gamification.qualify_referrals('2026-11-30 12:00+03') = 0, 'the switch off stops the sweep');
  perform pg_temp.check(pg_temp.state(d) = 'paid', 'nothing is revoked while the switch is off');

  -- The admin view.
  perform pg_temp.check(
    (select count(*) from gamification.referral_invitations where referrer_id = a) = 4,
    'the admin view lists every invitation');
  perform pg_temp.check(
    (select revoke_reason from gamification.referral_invitations where invitee_id = b) = 'inactive_7_days',
    'the admin view shows why a point was taken back');
  perform pg_temp.check(
    (select last_prediction_at from gamification.referral_invitations where invitee_id = c) = '2026-10-08 12:00+03',
    'the admin view shows the last prediction');
end $$;

rollback;
