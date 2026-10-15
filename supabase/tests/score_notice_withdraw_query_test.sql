-- Test for PostgresScoreAnnouncementRepository._withdrawSql (batch 143,
-- audit L-27): a corrected result removes the "you called it exactly"
-- notification of everyone who no longer called it, keeps the others',
-- touches no other kind or fixture, and an empty keep list removes them
-- all. Keep the body identical to the adapter's constant. Rolled back at
-- the end.
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
  RETURNING 1
)
SELECT count(*)::int AS withdrawn FROM gone
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0143-4000-8000-000000000001', 'w1@t.io', now()),
  ('00000000-0143-4000-8000-000000000002', 'w2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0143-4000-8000-000000000001', 'w1@t.io', 'Still Exact'),
  ('00000000-0143-4000-8000-000000000002', 'w2@t.io', 'No Longer');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0143-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0143-4000-8000-0000000000e1', '00000000-0143-4000-8000-0000000000c1',
        '07/2099', '2099-07-01', '2099-08-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0143-4000-8000-0000000000a1', '00000000-0143-4000-8000-0000000000e1',
   '00000000-0143-4000-8000-000000000001', '2099-07-01'),
  ('00000000-0143-4000-8000-0000000000a2', '00000000-0143-4000-8000-0000000000e1',
   '00000000-0143-4000-8000-000000000002', '2099-07-01');

-- Both called fixture f1 exactly; the second also has an f2 notice and an
-- unrelated announcement.
insert into notification.notifications (id, recipient_id, kind, subject_ref) values
  ('00000000-0143-4000-8000-0000000000b1', '00000000-0143-4000-8000-000000000001',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f1'),
  ('00000000-0143-4000-8000-0000000000b2', '00000000-0143-4000-8000-000000000002',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f1'),
  ('00000000-0143-4000-8000-0000000000b3', '00000000-0143-4000-8000-000000000002',
   'fixture_scored', 'fixture:00000000-0143-4000-8000-0000000000f2');

do $$
begin
  -- The correction keeps only the first player as an exact caller of f1.
  perform pg_temp.check(
    pg_temp.withdraw('fixture:00000000-0143-4000-8000-0000000000f1',
                     '00000000-0143-4000-8000-0000000000a1') = 1,
    'one notice withdrawn');
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
    exists (select 1 from notification.notifications
             where id = '00000000-0143-4000-8000-0000000000b3'),
    'still only that fixture');
end $$;

rollback;
