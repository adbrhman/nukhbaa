-- ============================================================================
-- Migration 0114: an idle invitee is no longer suspended
--
-- MODIFY-ONLY. One redefined function (same signature) and a one-time
-- reinstatement of the accounts the old sweep suspended. No row is deleted.
--
-- Since 0075, an invitee who sent no prediction for 7 days lost the
-- inviter's point (a compensating `referral_revoked`, reason
-- `inactive_7_days`) AND had the account suspended: a friend who really
-- came by invitation, then travelled or simply found no matches that week
-- (an international break), opened the app to "this account is suspended"
-- with no reason (audit M-21). Taking the point back is enough to stop a
-- fake invitation paying; a suspension punished the person, not the
-- cheat. Decided 2026-10-16 (batch 150): the point is still taken back,
-- the account is left alone.
--
-- The accounts the sweep already suspended are reinstated here, once:
-- suspended, a plain user, revoked by the sweep for idleness, and never
-- suspended by an admin (no `user_suspended` row in admin.audit_log names
-- them). An account an admin suspended keeps its suspension. There is no
-- actor to write an audit row for; this file is the record.
--
-- Forward-only, guarded. Safe to re-run: the reinstatement finds nobody the
-- second time, and the function is replaced with the same body.
-- ============================================================================

begin;

create or replace function gamification.expire_idle_referrals(
  p_now timestamptz default now()
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_rows integer;
begin
  create temporary table if not exists pg_temp.referral_idle (
    invitee_id uuid primary key,
    referrer_id uuid not null,
    last_activity timestamptz not null
  ) on commit drop;
  truncate pg_temp.referral_idle;

  insert into pg_temp.referral_idle (invitee_id, referrer_id, last_activity)
  select q.ref_id,
         q.user_id,
         greatest(
           q.occurred_at,
           coalesce((
             select max(fp.submitted_at)
               from competition.participants p
               join prediction.fixture_predictions fp
                 on fp.participant_id = p.id
              where p.user_id = q.ref_id
           ), q.occurred_at)
         )
    from gamification.events q
   where q.event_type = 'referral_qualified'
     and q.occurred_at <= p_now
     and not exists (
       select 1 from gamification.events r
        where r.event_type = 'referral_revoked'
          and r.ref_id = q.ref_id
     );

  delete from pg_temp.referral_idle
   where last_activity > p_now - interval '7 days';

  insert into gamification.events
    (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
     rule_version, occurred_at)
  select gen_random_uuid(), i.referrer_id, 'referral_revoked',
         jsonb_build_object(
           'invitee_id', i.invitee_id,
           'reason', 'inactive_7_days',
           'last_activity', i.last_activity,
           'automatic', true),
         'user', i.invitee_id,
         'referral_revoked:' || i.invitee_id::text,
         1, p_now
    from pg_temp.referral_idle i
  on conflict (dedupe_key) do nothing;
  get diagnostics v_rows = row_count;

  -- No suspension (0114, audit M-21): the invitee keeps playing.

  truncate pg_temp.referral_idle;
  return v_rows;
end;
$$;

comment on function gamification.expire_idle_referrals(timestamptz) is
  'Takes back (referral_revoked, reason inactive_7_days) every paid '
  'invitation whose invitee sent no prediction for 7 days. The account is '
  'left active (0114; 0075 suspended it). Called by qualify_referrals.';

-- The accounts the old sweep suspended, and no admin did.
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

insert into ops.applied_migrations (version)
values ('0114_idle_invitee_not_suspended')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0114_idle_invitee_not_suspended';            -- one row
-- select count(*) from identity.users u
--  where u.status = 'suspended'
--    and exists (select 1 from gamification.events e
--                 where e.event_type = 'referral_revoked'
--                   and e.ref_id = u.id
--                   and e.payload ->> 'reason' = 'inactive_7_days')
--    and not exists (select 1 from admin.audit_log a
--                     where a.action = 'user_suspended'
--                       and a.target_ref = u.id::text);           -- 0
