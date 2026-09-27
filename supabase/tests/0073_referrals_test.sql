-- End-to-end tests for migration 0073 (invitations), against a real
-- Postgres with every migration applied. Run by .github/workflows/db-tests.yml.
-- Everything happens inside one transaction that is rolled back.
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

create function pg_temp.expect_error(stmt text, label text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    raise notice 'ok - % (%)', label, sqlerrm;
    return;
  end;
  raise exception 'FAILED: % (no error raised)', label;
end $$;

-- A user: auth row (confirmed unless told otherwise) + platform row.
create function pg_temp.mk_user(n int, created timestamptz, confirmed boolean default true)
returns uuid language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at)
  values (v, 'u' || n || '@t.io', case when confirmed then created end);
  insert into identity.users (id, email, display_name, created_at)
  values (v, 'u' || n || '@t.io', 'User ' || n, created);
  return v;
end $$;

-- Monthly contests: October and November 2026.
insert into competition.competitions (id, name, format, visibility)
values ('c7300000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7300000-0000-4000-8000-000000000010', 'c7300000-0000-4000-8000-000000000001', '10/2026', '2026-10-01', '2026-11-01'),
  ('c7300000-0000-4000-8000-000000000011', 'c7300000-0000-4000-8000-000000000001', '11/2026', '2026-11-01', '2026-12-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c7300000-0000-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2026-10-05 18:00+03'),
  ('c7300000-0000-4000-8000-0000000000f2', 'Ittihad', 'Ahli', '2026-10-06 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c7300000-0000-4000-8000-000000000010', 'c7300000-0000-4000-8000-0000000000f1', 0),
  ('c7300000-0000-4000-8000-000000000010', 'c7300000-0000-4000-8000-0000000000f2', 1);

-- Makes a user play: joins October, predicts fixture f, and the fixture is
-- graded with the given grade.
create function pg_temp.play(u uuid, f uuid, grade text) returns void
language plpgsql as $$
declare pid uuid := gen_random_uuid();
begin
  insert into competition.participants (id, season_id, user_id, joined_at)
  values (pid, 'c7300000-0000-4000-8000-000000000010', u, '2026-10-01')
  on conflict (season_id, user_id) do nothing;
  select id into pid from competition.participants
   where season_id = 'c7300000-0000-4000-8000-000000000010' and user_id = u;
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values (gen_random_uuid(), f, pid, 1, 0, false, '2026-10-05 12:00+03');
  insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
  values (f, pid, 1, grade, case grade when 'exact_scoreline' then 3 else 0 end, '2026-10-05 21:00+03');
end $$;

-- Reads one invitee's event types, in order.
create function pg_temp.events_of(invitee uuid) returns text
language sql as $$
  select coalesce(string_agg(event_type, ',' order by occurred_at, event_type), '')
    from gamification.events where ref_id = invitee
$$;

do $$
declare
  a uuid; b uuid; c uuid; d uuid; e uuid; y uuid; old uuid; newer uuid; x uuid;
  unconfirmed uuid; s1 uuid; s2 uuid;
  code_a text; code_b text; code_x text; r text; n int;
  t_oct timestamptz := '2026-10-10 12:00+03';
begin
  a := pg_temp.mk_user(1, '2026-09-01');
  x := pg_temp.mk_user(2, '2026-09-01');

  -- 1. The switch: nothing is accepted while the flag is off.
  code_a := gamification.ensure_referral_code(a);
  b := pg_temp.mk_user(3, '2026-10-01 10:00+03');
  perform pg_temp.check(
    gamification.claim_referral(b, code_a, '1.1.1.1', 'inst-b', '2026-10-01 11:00+03') = 'disabled',
    'claims are refused while the referrals flag is off');
  update gamification.feature_flags set enabled = true where flag_key = 'referrals';

  -- 2. One fixed code per user.
  perform pg_temp.check(code_a ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$', 'the code has the 8-character shape');
  perform pg_temp.check(gamification.ensure_referral_code(a) = code_a, 'the code is fixed: asking again returns the same code');
  perform pg_temp.expect_error(
    format('update gamification.referral_codes set code = %L where user_id = %L', 'ABCDEFGH', a),
    'a code cannot be changed');
  perform pg_temp.expect_error(
    format('delete from gamification.referral_codes where user_id = %L', a),
    'a code cannot be deleted');

  -- 3. Registration and attribution.
  perform pg_temp.check(
    gamification.claim_referral(b, lower(code_a), '1.1.1.1', 'inst-b', '2026-10-01 11:00+03') = 'claimed',
    'a new account claims its inviter''s code (case-insensitive)');
  perform pg_temp.check(
    (select referrer_id from gamification.referrals where invitee_id = b) = a,
    'the invitation names the inviter');
  perform pg_temp.check(
    (select ip_hash is not null and ip_hash <> '1.1.1.1' and install_hash <> 'inst-b'
       from gamification.referrals where invitee_id = b),
    'the network and install are stored hashed, never raw');
  perform pg_temp.check(pg_temp.events_of(b) = '', 'signing up alone pays nothing');

  -- 4. One inviter per invitee, never changed.
  code_x := gamification.ensure_referral_code(x);
  perform pg_temp.check(
    gamification.claim_referral(b, code_x, '1.1.1.1', 'inst-b', '2026-10-01 11:05+03') = 'already_claimed',
    'a second claim with another code is refused');
  perform pg_temp.check(
    (select referrer_id from gamification.referrals where invitee_id = b) = a,
    'the inviter did not change');
  perform pg_temp.expect_error(
    format('update gamification.referrals set referrer_id = %L where invitee_id = %L', x, b),
    'the inviter cannot be changed by UPDATE');
  perform pg_temp.expect_error(
    format('delete from gamification.referrals where invitee_id = %L', b),
    'an invitation cannot be deleted');
  perform pg_temp.expect_error(
    format('insert into gamification.referrals (invitee_id, referrer_id, code, claimed_at) values (%L, %L, %L, now())', b, x, code_x),
    'the primary key refuses a second inviter for the same invitee');

  -- 5. No self-invitation.
  code_b := gamification.ensure_referral_code(b);
  perform pg_temp.check(
    gamification.claim_referral(b, code_b, null, null, '2026-10-01 11:10+03') in ('already_claimed', 'self_referral'),
    'an invitee cannot name its own code');
  c := pg_temp.mk_user(4, '2026-10-02 10:00+03');
  perform pg_temp.check(
    gamification.claim_referral(c, gamification.ensure_referral_code(c), null, null, '2026-10-02 10:30+03') = 'self_referral',
    'a user cannot invite itself');
  perform pg_temp.expect_error(
    format('insert into gamification.referrals (invitee_id, referrer_id, code, claimed_at) values (%L, %L, %L, %L)',
           c, c, gamification.ensure_referral_code(c), '2026-10-02 10:30+03'),
    'a self-invitation written directly is refused');

  -- 6. Bad codes and closed windows.
  perform pg_temp.check(gamification.claim_referral(c, 'abc', null, null, '2026-10-02 10:30+03') = 'invalid_code', 'a malformed code is refused');
  perform pg_temp.check(gamification.claim_referral(c, 'ZZZZZZZZ', null, null, '2026-10-02 10:30+03') = 'unknown_code', 'an unknown code is refused');
  old := pg_temp.mk_user(5, '2026-09-20');
  perform pg_temp.check(
    gamification.claim_referral(old, code_a, null, null, '2026-10-02 10:30+03') = 'window_closed',
    'an account older than 24 hours cannot be attributed');
  newer := pg_temp.mk_user(6, '2026-10-03 09:00+03');
  perform pg_temp.check(
    gamification.claim_referral(c, gamification.ensure_referral_code(newer), null, null, '2026-10-03 09:30+03') = 'window_closed',
    'an inviter newer than the invitee is refused');
  perform pg_temp.expect_error(
    format('insert into gamification.referrals (invitee_id, referrer_id, code, claimed_at) values (%L, %L, %L, %L)',
           old, a, code_a, '2026-10-02 10:30+03'),
    'the trigger refuses a late claim written directly');

  -- 7. Qualification needs a real player.
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 0, 'no pay before the invitee plays');
  perform pg_temp.play(b, 'c7300000-0000-4000-8000-0000000000f1', 'pending');
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 0, 'no pay while the prediction is not graded');
  perform pg_temp.play(b, 'c7300000-0000-4000-8000-0000000000f2', 'incorrect');
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 1, 'pay once the invitee has a graded prediction (right or wrong)');
  perform pg_temp.check(pg_temp.events_of(b) = 'referral_qualified', 'the inviter holds one referral_qualified event');
  perform pg_temp.check(
    (select user_id from gamification.events where ref_id = b) = a,
    'the event belongs to the inviter');

  -- 8. Idempotency.
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 0, 'a second run pays nothing');
  perform pg_temp.check(gamification.qualify_referrals(t_oct + interval '1 day') = 0, 'a later run pays nothing either');
  perform pg_temp.expect_error(
    format($f$insert into gamification.events (id, user_id, event_type, ref_type, ref_id, dedupe_key, occurred_at)
              values (gen_random_uuid(), %L, 'referral_qualified', 'user', %L, %L, now())$f$,
           a, b, 'referral_qualified:' || b),
    'the UNIQUE dedupe_key refuses a second payment for the same invitee');
  perform pg_temp.expect_error(
    format($f$insert into gamification.events (id, user_id, event_type, ref_type, ref_id, dedupe_key, occurred_at)
              values (gen_random_uuid(), %L, 'referral_qualified', 'user', %L, %L, now())$f$,
           x, c, 'referral_qualified:' || c),
    'a payment without a real invitation is refused');

  -- 9. Unconfirmed accounts are not paid.
  unconfirmed := pg_temp.mk_user(7, '2026-10-04 09:00+03', false);
  perform pg_temp.check(gamification.claim_referral(unconfirmed, code_a, '2.2.2.2', 'inst-u', '2026-10-04 09:10+03') = 'claimed', 'an unconfirmed account can claim');
  perform pg_temp.play(unconfirmed, 'c7300000-0000-4000-8000-0000000000f1', 'exact_scoreline');
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 0, 'an unconfirmed invitee is not paid');
  update auth.users set email_confirmed_at = '2026-10-04 10:00+03' where id = unconfirmed;
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 1, 'paid once the account is confirmed');

  -- 10. Suspicious invitations are held, then decided by an admin.
  s1 := pg_temp.mk_user(8, '2026-10-05 09:00+03');
  s2 := pg_temp.mk_user(9, '2026-10-05 09:30+03');
  perform gamification.claim_referral(s1, code_a, '9.9.9.9', 'inst-s1', '2026-10-05 09:05+03');
  perform gamification.claim_referral(s2, code_a, '9.9.9.9', 'inst-s2', '2026-10-05 09:35+03');
  perform pg_temp.play(s1, 'c7300000-0000-4000-8000-0000000000f1', 'correct_outcome');
  perform pg_temp.play(s2, 'c7300000-0000-4000-8000-0000000000f1', 'correct_outcome');
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 2, 'two invitees on one network are processed');
  perform pg_temp.check(pg_temp.events_of(s1) = 'referral_held' and pg_temp.events_of(s2) = 'referral_held',
    'both are held, not paid and not rejected');
  perform pg_temp.check(
    (select payload->'reasons' ? 'shared_network' from gamification.events where ref_id = s1),
    'the hold records its reason');
  perform pg_temp.check(gamification.review_referral(s1, 'approve', x, '') = 'reason_required', 'a decision needs a reason');
  perform pg_temp.check(gamification.review_referral(s1, 'approve', x, 'brothers, same house', t_oct) = 'approved', 'an admin approves a held invitation');
  perform pg_temp.check(gamification.review_referral(s2, 'reject', x, 'second account', t_oct) = 'rejected', 'an admin rejects a held invitation');
  perform pg_temp.check(gamification.review_referral(s2, 'approve', x, 'changed mind', t_oct) = 'already_decided', 'a rejected invitation cannot be paid later');
  perform pg_temp.check(gamification.review_referral(b, 'approve', x, 'not held', t_oct) = 'not_held', 'only a held invitation can be approved');
  perform pg_temp.check(gamification.qualify_referrals(t_oct) = 0, 'decided invitations are not processed again');

  -- The inviter's own install is held too.
  perform gamification.mark_referral_install(a, 'inst-of-a', '2026-10-01');
  d := pg_temp.mk_user(10, '2026-10-06 09:00+03');
  perform gamification.claim_referral(d, code_a, '3.3.3.3', 'inst-of-a', '2026-10-06 09:05+03');
  perform pg_temp.play(d, 'c7300000-0000-4000-8000-0000000000f1', 'incorrect');
  perform gamification.qualify_referrals(t_oct);
  perform pg_temp.check(
    (select payload->'reasons' ? 'inviter_install' from gamification.events where ref_id = d),
    'an invitee on the inviter''s own install is held');

  -- A burst of claims for one inviter is held.
  y := pg_temp.mk_user(300, '2026-09-01');
  for n in 1..11 loop
    e := pg_temp.mk_user(300 + n, '2026-10-08 09:00+03');
    perform gamification.claim_referral(e, gamification.ensure_referral_code(y), '20.0.0.' || n, 'burst-' || n, '2026-10-08 10:00+03');
    perform pg_temp.play(e, 'c7300000-0000-4000-8000-0000000000f1', 'incorrect');
  end loop;
  perform gamification.qualify_referrals(t_oct);
  perform pg_temp.check(
    (select count(*) = 11 and bool_and(payload->'reasons' ? 'burst')
       from gamification.events where user_id = y and event_type = 'referral_held'),
    'eleven claims in one day for one inviter are all held');
  perform pg_temp.check(
    not exists (select 1 from gamification.referral_month_points where user_id = y),
    'held invitations pay no points');

  -- 11. Monthly points: October so far = b, unconfirmed, s1 = 3.
  perform pg_temp.check(
    (select referral_points from gamification.referral_month_points
      where user_id = a and label = '10/2026') = 3,
    'the inviter has 3 invitation points in October');
  perform pg_temp.check(
    not exists (select 1 from gamification.referral_month_points where user_id = x),
    'an admin who only reviewed has no points');

  -- Revocation is a compensating event, never a delete.
  perform pg_temp.check(gamification.review_referral(unconfirmed, 'revoke', x, 'fake account found', t_oct) = 'revoked', 'a paid invitation can be revoked');
  perform pg_temp.check(gamification.review_referral(unconfirmed, 'revoke', x, 'again', t_oct) = 'already_decided', 'a revocation happens once');
  perform pg_temp.check(pg_temp.events_of(unconfirmed) = 'referral_qualified,referral_revoked', 'the payment is still in the history');
  perform pg_temp.check(
    (select referral_points from gamification.referral_month_points
      where user_id = a and label = '10/2026') = 2,
    'a revoked invitation leaves the monthly points');
  perform pg_temp.check(gamification.review_referral(b, 'revoke', x, '??', t_oct) = 'reason_required', 'a revocation needs a real reason');

  -- The cap: 21 more paid invitations in October, one a day -> 23 paid,
  -- 20 points.
  for n in 1..21 loop
    e := pg_temp.mk_user(100 + n, timestamptz '2026-10-07 09:00+03' + (n - 1) * interval '1 day');
    perform gamification.claim_referral(e, code_a, '10.0.0.' || n, 'inst-' || n,
      timestamptz '2026-10-07 09:05+03' + (n - 1) * interval '1 day');
    perform pg_temp.play(e, 'c7300000-0000-4000-8000-0000000000f1', 'incorrect');
  end loop;
  perform gamification.qualify_referrals('2026-10-28 12:00+03');
  perform pg_temp.check(
    (select referral_points = 20 and qualified_count > 20
       from gamification.referral_month_points
      where user_id = a and label = '10/2026'),
    'monthly invitation points are capped at 20');

  -- A new month starts from zero, the history stays.
  perform pg_temp.check(
    not exists (select 1 from gamification.referral_month_points
                 where user_id = a and label = '11/2026'),
    'November starts with no invitation points');
  e := pg_temp.mk_user(200, '2026-10-30 09:00+03');
  perform gamification.claim_referral(e, code_a, '4.4.4.4', 'inst-200', '2026-10-30 09:05+03');
  perform pg_temp.play(e, 'c7300000-0000-4000-8000-0000000000f1', 'incorrect');
  perform gamification.qualify_referrals('2026-11-02 12:00+03');
  perform pg_temp.check(
    (select referral_points from gamification.referral_month_points
      where user_id = a and label = '11/2026') = 1,
    'an invitation paid in November counts in November');
  perform pg_temp.check(
    (select referral_points from gamification.referral_month_points
      where user_id = a and label = '10/2026') = 20,
    'October keeps its own total');

  -- 12. Season total: the capped months added up (20 + 1).
  perform pg_temp.check(
    (select referral_points from gamification.referral_season_points
      where user_id = a and season_start_year = 2026) = 21,
    'the sporting-season total is the sum of the capped monthly points');

  -- 13. Nothing here touched prediction points.
  perform pg_temp.check(
    not exists (select 1 from ledger.fixture_point_entries e
                  join competition.participants p on p.id = e.participant_id
                 where p.user_id = a),
    'invitation points never enter the ledger');
  perform pg_temp.check(
    not exists (select 1 from leaderboard.season_fixture_standings s
                  join competition.participants p on p.id = s.participant_id
                 where p.user_id = a),
    'the inviter''s monthly prediction total is untouched');

  -- 14. The switch off again: no new payments.
  update gamification.feature_flags set enabled = false where flag_key = 'referrals';
  perform pg_temp.check(gamification.qualify_referrals('2026-11-03') = 0, 'nothing is paid while the flag is off');
end $$;

rollback;
