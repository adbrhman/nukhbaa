-- End-to-end test for migration 0208: the audit trail takes the token of a
-- support reading of a player's open predictions (script 261). Also the
-- statement PostgresOffBoardParticipants runs (copied below): the
-- participants of a suspended or hidden account, whom no board of a match
-- shows. Rolled back at the end.
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
  admin_id uuid := '00000000-0000-4000-8208-000000000001';
  player_id uuid := '00000000-0000-4000-8208-000000000002';
begin
  perform pg_temp.check(
    exists (
      select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'admin' and t.typname = 'audit_action'
         and e.enumlabel = 'support_predictions_viewed'),
    'admin.audit_action has support_predictions_viewed');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0208_support_predictions_viewed_audit'),
    '0208 records itself');

  insert into auth.users (id, email, email_confirmed_at) values
    (admin_id, 'adm208@t.io', now()),
    (player_id, 'p208@t.io', now());
  insert into identity.users (id, email, display_name, role, created_at) values
    (admin_id, 'adm208@t.io', 'Admin 208', 'admin', now()),
    (player_id, 'p208@t.io', 'Player 208', 'user', now());

  insert into admin.audit_log (id, actor_id, action, target_ref, reason)
  values (gen_random_uuid(), admin_id, 'support_predictions_viewed',
          player_id::text, 'يقول إن توقعه لم يُحفظ');

  perform pg_temp.check(
    (select count(*) from admin.audit_log
      where action = 'support_predictions_viewed'
        and target_ref = player_id::text
        and reason = 'يقول إن توقعه لم يُحفظ') = 1,
    'a support reading is recorded by the player and its reason');
end $$;

create function pg_temp.off_board() returns setof uuid
language sql as $f$
SELECT p.id AS participant_id
FROM competition.participants p
JOIN identity.users u ON u.id = p.user_id
WHERE u.status = 'suspended' OR u.hidden_at IS NOT NULL
$f$;

do $$
declare
  season uuid := 'c2080000-0000-4000-8000-000000000010';
begin
  insert into auth.users (id, email, email_confirmed_at) values
    ('00000000-0000-4000-8208-000000000011', 'a208@t.io', now()),
    ('00000000-0000-4000-8208-000000000012', 's208@t.io', now()),
    ('00000000-0000-4000-8208-000000000013', 'h208@t.io', now());
  insert into identity.users (id, email, display_name, status, hidden_at) values
    ('00000000-0000-4000-8208-000000000011', 'a208@t.io', 'Active', 'active', null),
    ('00000000-0000-4000-8208-000000000012', 's208@t.io', 'Suspended', 'suspended', null),
    ('00000000-0000-4000-8208-000000000013', 'h208@t.io', 'Hidden', 'active', now());
  insert into competition.competitions (id, name, format, visibility)
  values ('c2080000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
  insert into competition.seasons (id, competition_id, label, start_at, end_at)
  values (season, 'c2080000-0000-4000-8000-000000000001', '08/2099', '2099-08-01', '2099-09-01');
  insert into competition.participants (id, season_id, user_id, joined_at) values
    ('c2080000-0000-4000-8000-0000000000a1', season, '00000000-0000-4000-8208-000000000011', '2099-08-01'),
    ('c2080000-0000-4000-8000-0000000000a2', season, '00000000-0000-4000-8208-000000000012', '2099-08-01'),
    ('c2080000-0000-4000-8000-0000000000a3', season, '00000000-0000-4000-8208-000000000013', '2099-08-01');

  perform pg_temp.check(
    (select array_agg(x order by x) from pg_temp.off_board() x
      where x::text like 'c2080000%')
      = array['c2080000-0000-4000-8000-0000000000a2',
              'c2080000-0000-4000-8000-0000000000a3']::uuid[],
    'off the boards: the suspended and the hidden, not the active');
end $$;

rollback;
