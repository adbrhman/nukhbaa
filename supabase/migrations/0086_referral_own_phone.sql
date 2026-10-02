-- ============================================================================
-- Migration 0086: an invitation counts only from the app, on the invitee's
-- own phone
--
-- Decided 2026-10-03 by the owner: invitations only break ties, so the rule
-- stays simple -- whoever is invited must use the app on a phone that is not
-- the inviter's. Sharing a network (one house, one carrier) is fine.
--
-- gamification.claim_referral gains two refusals, checked after every
-- existing one and before anything is written:
--   * app_required -- no install id: the claim came from the browser, where
--     a phone cannot be recognised (the web build no longer sends one);
--   * same_device  -- the install is one the inviter was seen with (the
--     inviter opens the invitation page in the app to share the link, which
--     records that phone, migration 0073).
-- A refused claim writes nothing, so the invitee can still claim from the
-- app on a phone of its own within the existing 24 hours.
--
-- ADDITIVE: the function is replaced with the same signature; no row of any
-- table is written, changed or removed. Safe to re-run.
-- ============================================================================

begin;

create or replace function gamification.claim_referral(
  p_invitee uuid,
  p_code text,
  p_ip text,
  p_install_id text,
  p_now timestamptz default now()
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_referrer uuid;
  v_invitee_created timestamptz;
  v_referrer_created timestamptz;
begin
  if not coalesce((
    select f.enabled from gamification.feature_flags f
     where f.flag_key = 'referrals'), false) then
    return 'disabled';
  end if;
  if exists (select 1 from gamification.referrals r where r.invitee_id = p_invitee) then
    return 'already_claimed';
  end if;
  if v_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$' then
    return 'invalid_code';
  end if;
  select c.user_id into v_referrer
    from gamification.referral_codes c where c.code = v_code;
  if v_referrer is null then
    return 'unknown_code';
  end if;
  if v_referrer = p_invitee then
    return 'self_referral';
  end if;
  select u.created_at into v_invitee_created
    from identity.users u where u.id = p_invitee;
  select u.created_at into v_referrer_created
    from identity.users u where u.id = v_referrer;
  if v_invitee_created is null
     or p_now > v_invitee_created + interval '24 hours'
     or v_referrer_created >= v_invitee_created then
    return 'window_closed';
  end if;
  -- 0086: the invitee must be on the app, on a phone of its own. A claim
  -- without an install id comes from the browser (the web build sends
  -- none), where the phone cannot be told apart; an install the inviter was
  -- seen with is the inviter's own phone. Neither is recorded, so the
  -- invitee can still claim from the app on another phone within 24 hours.
  if nullif(btrim(coalesce(p_install_id, '')), '') is null then
    return 'app_required';
  end if;
  if exists (
    select 1 from gamification.referral_install_marks m
     where m.user_id = v_referrer
       and m.install_hash = gamification.referral_hash('install', p_install_id)
  ) then
    return 'same_device';
  end if;
  insert into gamification.referrals
    (invitee_id, referrer_id, code, claimed_at, ip_hash, install_hash)
  values (
    p_invitee, v_referrer, v_code, p_now,
    gamification.referral_hash('ip', p_ip),
    gamification.referral_hash('install', p_install_id)
  )
  on conflict (invitee_id) do nothing;
  if not found then
    return 'already_claimed';
  end if;
  perform gamification.mark_referral_install(p_invitee, p_install_id, p_now);
  return 'claimed';
end;
$$;

comment on function gamification.claim_referral(uuid, text, text, text, timestamptz) is
  'The invitee names the inviter''s code. Returns claimed | already_claimed | '
  'disabled | invalid_code | unknown_code | self_referral | window_closed | '
  'app_required | same_device (0086: only from the app, never on the '
  'inviter''s phone).';

insert into ops.applied_migrations (version)
values ('0086_referral_own_phone')
on conflict (version) do nothing;

commit;
