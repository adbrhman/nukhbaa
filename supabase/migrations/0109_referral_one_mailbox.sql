-- ============================================================================
-- Migration 0109: an account behind another account's mailbox earns no
-- invitation (audit M-22)
--
-- ADDITIVE / MODIFY-ONLY. One new function, one new index, and
-- gamification.claim_referral redefined with the same signature (0086's
-- body plus one refusal). No row of any table is written, changed or
-- removed.
--
-- Invitation points break ties on the month board and so can decide the
-- crown and its prize. A player could open accounts with aliases of one
-- Gmail address (name+1@gmail.com, n.ame@gmail.com), confirm each in the
-- same inbox, and claim his own code from each. gamification.
-- normalized_email folds an address the way mail providers do -- lower
-- case, the '+' tag dropped, and for gmail.com / googlemail.com the dots
-- dropped too -- and a claim from an account whose folded address belongs
-- to another account is refused as 'duplicate_account'. Nothing is
-- recorded, as with every refusal.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function gamification.normalized_email(p_email text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $f$
  select case
    when p_email is null then null
    when position('@' in btrim(p_email)) = 0 then lower(btrim(p_email))
    when lower(substr(btrim(p_email), position('@' in btrim(p_email)) + 1))
         in ('gmail.com', 'googlemail.com')
      then replace(
             split_part(lower(split_part(btrim(p_email), '@', 1)), '+', 1),
             '.', '') || '@gmail.com'
    else split_part(lower(split_part(btrim(p_email), '@', 1)), '+', 1)
         || '@' || lower(substr(btrim(p_email), position('@' in btrim(p_email)) + 1))
  end
$f$;

comment on function gamification.normalized_email(text) is
  'An e-mail address folded the way mail providers deliver it: lower case, '
  'the + tag dropped, and for gmail.com / googlemail.com the dots dropped '
  'and the domain made gmail.com (0109). Used to refuse an invitation from '
  'a second account behind one mailbox.';

create index if not exists users_email_normalized_idx
  on identity.users (gamification.normalized_email(email))
  where email is not null;

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
  -- 0109 (audit M-22): one mailbox, one account. Gmail ignores dots and
  -- anything after '+', and most providers ignore the '+' tag, so
  -- name+1@gmail.com and n.ame@gmail.com are the same person as
  -- name@gmail.com. Such a second account cannot earn its inviter a point.
  if exists (
    select 1
      from identity.users me
      join identity.users other
        on other.id <> me.id
       and other.email is not null
       and gamification.normalized_email(other.email)
           = gamification.normalized_email(me.email)
     where me.id = p_invitee
       and me.email is not null
  ) then
    return 'duplicate_account';
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
  'duplicate_account | app_required | same_device (0086: only from the app, '
  'never on the inviter''s phone; 0109: never from a second account behind '
  'one mailbox).';

insert into ops.applied_migrations (version)
values ('0109_referral_one_mailbox')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0109_referral_one_mailbox';                           -- 1 row
-- select gamification.normalized_email('N.Ame+1@GoogleMail.com');        -- name@gmail.com
