-- Test for PostgresScoreAnnouncementRepository._withdrawSql (batch 143,
-- audit L-27; batch 216, audit 37): a corrected result removes the "you
-- called it exactly" notification of everyone who no longer called it,
-- keeps the others', touches no other kind or fixture, and an empty keep
-- list removes them all. A push still queued for the end of the quiet hours
-- under a removed notification's id is marked claimed, so it never goes
-- out; a push already delivered and every other queued push are left as
-- they are. Keep the body identical to the adapter's constant (script 216
-- compares them). Rolled back at the end.
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

-- PostgresScoreAnnouncementRepository._withdrawSql
create function pg_temp.withdraw(p_subject_ref text, p_keep_ids text)
returns int
language sql as $q$
WITH gone AS (
  DELETE FROM notification.notifications n
  WHERE n.kind = 'fixture_scored'
    AND n.subject_ref = p_subject_ref
    AND NOT EXISTS (
      SELECT 1
      FROM competition.participants p
      WHERE p.id::text = ANY(string_to_array(p_keep_ids, ','))
        AND p.user_id = n.recipient_id
    )
  RETURNING n.id
),
held AS (
  UPDATE notification.notification_queue q
  SET sent_at = now()
  WHERE q.id IN (SELECT id FROM gone)
    AND q.sent_at IS NULL
  RETURNING 1
)
SELECT count(*)::int AS withdrawn FROM gone
$q$;

-- When the queued push [id] was claimed, or null while it waits.
create function pg_temp.sent_at(id uuid) returns timestamptz language sql as $$
  select q.sent_at from notification.notification_queue q where q.id = $1
$$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0143-4000-8000-000000000001', 'w1@t.io', now()),
  ('00000000-0143-4000-8000-000000000002', 'w2@t.io', now()),
  ('00000000-0143-4000-8000-000000000003', 'w3@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0143-4000-8000-000000000001', 'w1@t.io', 'Still Exact'),
  ('00000000-0143-4000-8000-000000000002', 'w2@t.io', 'No Longer'),
  ('00000000-0143-4000-8000-000000000003', 'w3@t.io', 'Already Rang');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0143-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0143-4000-8000-0000000000e1', '00000000-0143-4000-8000-0000000000c1',
        '07/2099', '2099-07-01', '2099-08-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0143-4000-8000-0000000000a1', '00000000-0143-4000-8000-0000000000e1',
   '00000000-0143-4000-8000-000000000001', '2099-07-01'),
  ('00000000-0143-4000-8000-0000000000a2', '00000000-0143-4000-8000-0000000000e1',
   '00000000-0143-4000-8000-000000000002', '2099-07-01'),
  ('00000000-0143-4000-8000-0000000000a3', '00000000-0143-4000-8000-0000000000e1',
   '00000000-0143-4000-8000-000000000003', '2099-07-01');

-- All three called fixture f1 exactly; the second also has an f2 notice.
insert into notification.notifications (id, recipient_id, kind, subject_ref) values
  ('00000000-0143-4000-8000-0000000000b1', '00000000-0143-4000-8000-000000000001',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f1'),
  ('00000000-0143-4000-8000-0000000000b2', '00000000-0143-4000-8000-000000000002',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f1'),
  ('00000000-0143-4000-8000-0000000000b3', '00000000-0143-4000-8000-000000000002',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f2'),
  ('00000000-0143-4000-8000-0000000000b4', '00000000-0143-4000-8000-000000000003',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f1');

-- Their pushes, queued under the notifications' ids (NotifyFixtureWinners):
-- the third one's already went out at 08:00. The second also waits for an
-- announcement, queued under an id of its own.
insert into notification.notification_queue (id, user_id, title, body, deliver_after, sent_at) values
  ('00000000-0143-4000-8000-0000000000b1', '00000000-0143-4000-8000-000000000001',
   'exact', '+3', '2099-07-02 05:00+00', null),
  ('00000000-0143-4000-8000-0000000000b2', '00000000-0143-4000-8000-000000000002',
   'exact', '+3', '2099-07-02 05:00+00', null),
  ('00000000-0143-4000-8000-0000000000b3', '00000000-0143-4000-8000-000000000002',
   'exact', '+3', '2099-07-02 05:00+00', null),
  ('00000000-0143-4000-8000-0000000000b4', '00000000-0143-4000-8000-000000000003',
   'exact', '+3', '2099-07-02 05:00+00', '2099-07-02 05:00+00'),
  ('00000000-0143-4000-8000-0000000000d1', '00000000-0143-4000-8000-000000000002',
   'news', 'an announcement', '2099-07-02 05:00+00', null);

do $$
begin
  -- The correction keeps only the first player as an exact caller of f1.
  perform pg_temp.check(
    pg_temp.withdraw('fixture:00000000-0143-4000-8000-0000000000f1',
                     '00000000-0143-4000-8000-0000000000a1') = 2,
    'two notices withdrawn');
  perform pg_temp.check(
    exists (select 1 from notification.notifications
             where id = '00000000-0143-4000-8000-0000000000b1'),
    'the player still exact keeps his notice');
  perform pg_temp.check(
    not exists (select 1 from notification.notifications
                 where id = '00000000-0143-4000-8000-0000000000b2'),
    'the player no longer exact loses his');
  perform pg_temp.check(
    exists (select 1 from notification.notifications
             where id = '00000000-0143-4000-8000-0000000000b3'),
    'another fixture''s notice is untouched');

  -- The queue (audit 37).
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b2') is not null,
    'the withdrawn notice''s waiting push is claimed: it never goes out');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b1') is null,
    'the player still exact still waits for his push');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b3') is null,
    'another fixture''s push still waits');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000d1') is null,
    'a push of another kind still waits');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b4') = '2099-07-02 05:00+00',
    'a push already delivered is left as it was');
  perform pg_temp.check(
    (select count(*) from notification.notification_queue) = 5,
    'no queued push is deleted');

  -- Run again with the same keep list: nothing more goes.
  perform pg_temp.check(
    pg_temp.withdraw('fixture:00000000-0143-4000-8000-0000000000f1',
                     '00000000-0143-4000-8000-0000000000a1') = 0,
    'a repeat withdraws nothing');

  -- A result with no exact caller left: an empty keep list removes them all.
  perform pg_temp.check(
    pg_temp.withdraw('fixture:00000000-0143-4000-8000-0000000000f1', '') = 1,
    'an empty keep list withdraws every notice of the fixture');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b1') is not null,
    'and claims its waiting push');
  perform pg_temp.check(
    exists (select 1 from notification.notifications
             where id = '00000000-0143-4000-8000-0000000000b3'),
    'still only that fixture');
  perform pg_temp.check(
    pg_temp.sent_at('00000000-0143-4000-8000-0000000000b3') is null,
    'and only that fixture''s pushes');
end $$;

rollback;
