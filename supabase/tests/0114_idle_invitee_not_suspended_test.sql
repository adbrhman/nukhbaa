-- Test for migration 0114 (batch 150, audit M-21): the idle sweep takes the
-- inviter's point back and leaves the invitee active, and the one-time
-- reinstatement returns only the accounts the old sweep suspended, never
-- one an admin suspended. Keep pg_temp.reinstate identical to the
-- migration's UPDATE. Rolled back at the end.
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

-- 0114's reinstatement.
create function pg_temp.reinstate() returns integer
language plpgsql as $$
declare
  v_rows integer;
begin
  update identity.users u
     set status = 'active'
   where u.status = 'suspended'
     and u.role = 'user'
     and exists (
       select 1
         from gamification.events e
        where e.event_type = 'referral_revoked'
          and e.ref_id = u.id
          and e.payload ->> 'reason' = 'inactive_7_days'
          and (e.payload ->> 'automatic')::boolean is true
     )
     and not exists (
       select 1
         from admin.audit_log a
        where a.action = 'user_suspended'
          and a.target_ref = u.id::text
     );
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

create function pg_temp.mk_user(n int, status text default 'active')
returns uuid language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8114-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, 'r' || n || '@t.io', now());
  -- The inviter (n = 1) is the oldest account, as an invitation requires.
  insert into identity.users (id, email, display_name, status, created_at)
  values (v, 'r' || n || '@t.io', 'Idle ' || n, status::identity.user_status,
          now() - make_interval(days => 10 - n));
  return v;
end $$;

create function pg_temp.revoked_for_idleness(inviter uuid, invitee uuid)
returns void language plpgsql as $$
begin
  insert into gamification.referrals (invitee_id, referrer_id, code, claimed_at)
  select invitee, inviter, gamification.ensure_referral_code(inviter),
         u.created_at + interval '1 minute'
    from identity.users u
   where u.id = invitee;
  -- Paid, then taken back for idleness, as the sweep does.
  insert into gamification.events
    (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
     rule_version, occurred_at)
  values (gen_random_uuid(), inviter, 'referral_qualified',
          jsonb_build_object('invitee_id', invitee),
          'user', invitee, 'referral_qualified:' || invitee::text, 1,
          now() - interval '8 days');
  insert into gamification.events
    (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
     rule_version, occurred_at)
  values (gen_random_uuid(), inviter, 'referral_revoked',
          jsonb_build_object('invitee_id', invitee, 'reason', 'inactive_7_days',
                             'automatic', true),
          'user', invitee, 'referral_revoked:' || invitee::text, 1, now());
end $$;

do $$
declare
  inviter uuid; swept uuid; by_admin uuid; other uuid; adm uuid;
begin
  inviter := pg_temp.mk_user(1);
  adm := pg_temp.mk_user(9);
  update identity.users set role = 'admin' where id = adm;

  -- Suspended by the old sweep: revoked for idleness, no admin row.
  swept := pg_temp.mk_user(2, 'suspended');
  perform pg_temp.revoked_for_idleness(inviter, swept);

  -- Revoked for idleness too, but an admin suspended it.
  by_admin := pg_temp.mk_user(3, 'suspended');
  perform pg_temp.revoked_for_idleness(inviter, by_admin);
  insert into admin.audit_log (id, actor_id, action, target_ref, reason)
  values (gen_random_uuid(), adm, 'user_suspended', by_admin::text, 'abuse');

  -- Suspended for another reason, never revoked for idleness.
  other := pg_temp.mk_user(4, 'suspended');

  perform pg_temp.check(pg_temp.reinstate() = 1, 'one account is reinstated');
  perform pg_temp.check(
    (select status::text from identity.users where id = swept) = 'active',
    'the account the sweep suspended is active again');
  perform pg_temp.check(
    (select status::text from identity.users where id = by_admin) = 'suspended',
    'an account an admin suspended stays suspended');
  perform pg_temp.check(
    (select status::text from identity.users where id = other) = 'suspended',
    'a suspension with no idle revocation is untouched');
  perform pg_temp.check(pg_temp.reinstate() = 0, 'a second run finds nobody');

  perform pg_temp.check(
    position('status = ''suspended''' in
      pg_get_functiondef('gamification.expire_idle_referrals(timestamptz)'::regprocedure)) = 0,
    'the sweep no longer suspends');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0114_idle_invitee_not_suspended'),
    'the migration is recorded');
end $$;

rollback;
