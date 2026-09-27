-- ============================================================================
-- Migration 0075: idle invitees, and the admin's view of invitations
--
-- ADDITIVE / MODIFY-ONLY. One new function, one redefined function (same
-- signature), one new view. No row is deleted: an idle invitee's point is
-- taken back with a compensating `referral_revoked` event (append-only) and
-- the account is SUSPENDED, never deleted (decided 2026-09-27; the no-delete
-- rule of 2026-09-09 stands). An admin can reinstate the account from the
-- existing user-sanction screen; the invitation itself stays revoked.
--
-- ## Idle (decided 2026-09-27)
-- A paid invitation whose invitee has sent no prediction for 7 consecutive
-- days since the later of (the payment, the last prediction) is revoked
-- (payload reason `inactive_7_days`) and the invitee's account is suspended.
-- It runs inside `qualify_referrals`, so the same 30-minute sweep and the
-- same `referrals` switch govern it: while the switch is off nothing is
-- paid and nothing is taken back. Each invitation can be revoked once (the
-- unique dedupe key), so a reinstated account is never suspended again for
-- the same invitation.
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

  -- Suspend, never delete. Only accounts still active; an admin account is
  -- never suspended by a sweep.
  update identity.users u
     set status = 'suspended'
    from pg_temp.referral_idle i
   where u.id = i.invitee_id
     and u.status = 'active'
     and u.role = 'user';

  truncate pg_temp.referral_idle;
  return v_rows;
end;
$$;

comment on function gamification.expire_idle_referrals(timestamptz) is
  'Takes back (referral_revoked, reason inactive_7_days) every paid '
  'invitation whose invitee sent no prediction for 7 days, and suspends '
  'that account. Never deletes. Called by qualify_referrals (0075).';

-- The sweep, redefined: the 0073 body plus the idle step at the end.
create or replace function gamification.qualify_referrals(
  p_now timestamptz default now()
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_step integer;
begin
  if not coalesce((
    select f.enabled from gamification.feature_flags f
     where f.flag_key = 'referrals'), false) then
    return 0;
  end if;

  create temporary table if not exists pg_temp.referral_candidates (
    invitee_id uuid primary key,
    referrer_id uuid not null,
    reasons text[] not null
  ) on commit drop;
  truncate pg_temp.referral_candidates;

  insert into pg_temp.referral_candidates (invitee_id, referrer_id, reasons)
  select r.invitee_id,
         r.referrer_id,
         array_remove(array[
           case when r.ip_hash is not null and exists (
             select 1 from gamification.referrals o
              where o.referrer_id = r.referrer_id
                and o.invitee_id <> r.invitee_id
                and o.ip_hash = r.ip_hash
                and o.claimed_at between r.claimed_at - interval '7 days'
                                     and r.claimed_at + interval '7 days'
           ) then 'shared_network' end,
           case when r.install_hash is not null and exists (
             select 1 from gamification.referrals o
              where o.invitee_id <> r.invitee_id
                and o.install_hash = r.install_hash
           ) then 'shared_install' end,
           case when r.install_hash is not null and exists (
             select 1 from gamification.referral_install_marks m
              where m.user_id = r.referrer_id
                and m.install_hash = r.install_hash
           ) then 'inviter_install' end,
           case when (
             select count(*) from gamification.referrals o
              where o.referrer_id = r.referrer_id
                and o.claimed_at between r.claimed_at - interval '24 hours'
                                     and r.claimed_at + interval '24 hours'
           ) > 10 then 'burst' end
         ], null)
    from gamification.referrals r
    join identity.users inv
      on inv.id = r.invitee_id and inv.status = 'active'
    join identity.users ref
      on ref.id = r.referrer_id and ref.status = 'active'
    join auth.users au
      on au.id = r.invitee_id and au.email_confirmed_at is not null
   where r.claimed_at <= p_now
     and not exists (
       select 1 from gamification.events e
        where e.ref_id = r.invitee_id
          and e.event_type in (
            'referral_held', 'referral_qualified', 'referral_rejected')
     )
     -- Entered a monthly contest, sent a valid prediction, and that
     -- prediction was graded on a decided fixture.
     and exists (
       select 1
         from competition.participants p
         join prediction.fixture_predictions fp
           on fp.participant_id = p.id
         join scoring.fixture_scores fs
           on fs.participant_id = p.id
          and fs.fixture_id = fp.fixture_id
          and fs.grade in ('exact_scoreline', 'correct_outcome', 'incorrect')
        where p.user_id = r.invitee_id
          and p.status = 'active'
          and fs.scored_at <= p_now
     );

  insert into gamification.events
    (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
     rule_version, occurred_at)
  select gen_random_uuid(), c.referrer_id,
         case when cardinality(c.reasons) = 0
              then 'referral_qualified' else 'referral_held' end,
         case when cardinality(c.reasons) = 0
              then jsonb_build_object('invitee_id', c.invitee_id)
              else jsonb_build_object('invitee_id', c.invitee_id,
                                      'reasons', to_jsonb(c.reasons)) end,
         'user', c.invitee_id,
         case when cardinality(c.reasons) = 0
              then 'referral_qualified:' else 'referral_held:' end
           || c.invitee_id::text,
         1, p_now
    from pg_temp.referral_candidates c
  on conflict (dedupe_key) do nothing;
  get diagnostics v_step = row_count;
  v_rows := v_rows + v_step;

  truncate pg_temp.referral_candidates;

  -- Then take back the invitations whose invitee went idle (0075).
  v_rows := v_rows + gamification.expire_idle_referrals(p_now);
  return v_rows;
end;
$$;


-- ---------------------------------------------------------------------------
-- The admin's view: one row per invitation, with its state.
-- ---------------------------------------------------------------------------
create or replace view gamification.referral_invitations as
  select
    r.invitee_id,
    iu.display_name as invitee_name,
    iu.status::text as invitee_status,
    r.referrer_id,
    ru.display_name as referrer_name,
    r.claimed_at,
    case
      when ev.revoked_at is not null then 'revoked'
      when ev.rejected_at is not null then 'rejected'
      when ev.paid_at is not null then 'paid'
      when ev.held_at is not null then 'held'
      else 'pending'
    end as state,
    ev.paid_at,
    ev.held_at,
    ev.revoked_at,
    ev.hold_reasons,
    ev.revoke_reason,
    (
      select max(fp.submitted_at)
        from competition.participants p
        join prediction.fixture_predictions fp
          on fp.participant_id = p.id
       where p.user_id = r.invitee_id
    ) as last_prediction_at
  from gamification.referrals r
  join identity.users iu on iu.id = r.invitee_id
  join identity.users ru on ru.id = r.referrer_id
  left join lateral (
    select
      max(e.occurred_at) filter (where e.event_type = 'referral_qualified') as paid_at,
      max(e.occurred_at) filter (where e.event_type = 'referral_held') as held_at,
      max(e.occurred_at) filter (where e.event_type = 'referral_revoked') as revoked_at,
      max(e.occurred_at) filter (where e.event_type = 'referral_rejected') as rejected_at,
      coalesce(array_to_string(array(
        select jsonb_array_elements_text(
          coalesce((
            select h.payload -> 'reasons' from gamification.events h
             where h.ref_id = r.invitee_id and h.event_type = 'referral_held'
             limit 1
          ), '[]'::jsonb))
      ), ','), '') as hold_reasons,
      max(e.payload ->> 'reason') filter (where e.event_type = 'referral_revoked') as revoke_reason
    from gamification.events e
    where e.ref_id = r.invitee_id
      and e.event_type like 'referral\_%'
  ) ev on true;

comment on view gamification.referral_invitations is
  'One row per invitation with its state (pending, held, paid, revoked, '
  'rejected), for the admin dashboard (0075). Server-only.';

revoke all on gamification.referral_invitations from anon, authenticated;
revoke execute on function gamification.expire_idle_referrals(timestamptz) from public, anon, authenticated;
revoke execute on function gamification.qualify_referrals(timestamptz) from public, anon, authenticated;

commit;
