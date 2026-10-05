-- End-to-end test for migration 0092: a duel notification row can be stored
-- against its challenge, is unique per (recipient, kind, subject_ref), and a
-- tap on a 'duel' push can be recorded.
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

do $$
declare
  t0 timestamptz := '2030-01-01 12:00+00';
  season uuid := '00000000-0092-4000-8092-000000000001';
  competition uuid := '00000000-0092-4000-8092-000000000002';
  fixture uuid := '00000000-0092-4000-8092-000000000003';
  u1 uuid := '00000000-0092-4000-8092-000000000011';
  u2 uuid := '00000000-0092-4000-8092-000000000012';
  p1 uuid := '00000000-0092-4000-8092-000000000021';
  c uuid;
  dup boolean := false;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u1, 'n1@t.io', now()), (u2, 'n2@t.io', now());
  insert into identity.users (id, email, display_name) values
    (u1, 'n1@t.io', 'Notice One'), (u2, 'n2@t.io', 'Notice Two');
  insert into competition.competitions (id, name, format, visibility)
    values (competition, 'Notice Test', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
    values (season, competition, 'Notice Season',
            '2029-12-01 00:00+00', '2030-02-01 00:00+00');
  insert into competition.participants (id, season_id, user_id, joined_at)
    values (p1, season, u1, t0 - interval '1 day');
  insert into competition.fixture_schedules
    (fixture_id, home_team, away_team, kickoff_at)
    values (fixture, 'Home', 'Away', t0 + interval '6 hours');
  insert into competition.season_fixtures (season_id, fixture_id, display_order)
    values (season, fixture, 1);

  select social.create_duel_challenge(u1, season, fixture, 1, u2, t0) into c;

  insert into notification.notifications
    (id, recipient_id, kind, actor_user_id, duel_challenge_id, subject_ref)
    values ('00000000-0092-4000-8092-000000000031', u2, 'duel_challenged',
            u1, c, 'duel_challenged:' || c);
  perform pg_temp.check(
    exists (select 1 from notification.notifications
             where duel_challenge_id = c and kind = 'duel_challenged'),
    'a duel_challenged notification references its challenge');

  begin
    insert into notification.notifications
      (id, recipient_id, kind, actor_user_id, duel_challenge_id, subject_ref)
      values ('00000000-0092-4000-8092-000000000032', u2, 'duel_challenged',
              u1, c, 'duel_challenged:' || c);
  exception when unique_violation then
    dup := true;
  end;
  perform pg_temp.check(dup, 'the same challenge is told once');

  insert into notification.notifications
    (id, recipient_id, kind, actor_user_id, duel_challenge_id, subject_ref)
    values ('00000000-0092-4000-8092-000000000033', u1, 'duel_accepted',
            u2, c, 'duel_accepted:' || c || ':' || u2);
  perform pg_temp.check(
    (select count(*) from notification.notifications
      where duel_challenge_id = c) = 2,
    'a duel_accepted notification is stored beside it');

  insert into notification.push_opens (user_id, link)
    values (u2, 'duel');
  perform pg_temp.check(
    exists (select 1 from notification.push_opens
             where user_id = u2 and link = 'duel'),
    'a tap on a duel push is recorded');
end $$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0092_duel_notifications'),
  'migration records itself');

rollback;
