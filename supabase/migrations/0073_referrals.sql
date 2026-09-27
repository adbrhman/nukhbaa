-- ============================================================================
-- Migration 0073: invitations (referrals) inside gamification
--
-- ADDITIVE ONLY. Three new tables and two views in the existing
-- `gamification` schema, four functions, one feature-flag row, and a guard
-- trigger on the existing append-only `gamification.events`. No existing
-- row, column or table is changed or deleted.
--
-- ## The rules (decided 2026-09-27)
-- * Every user has ONE fixed invitation code (`referral_codes`), never
--   changed.
-- * Signing up alone pays nothing. An invitation is CLAIMED right after the
--   invitee's account is created (`claim_referral`, within 24 hours of the
--   invitee's `identity.users.created_at`), and it names exactly one
--   inviter, forever: `referrals.invitee_id` is the primary key and the
--   table rejects UPDATE and DELETE.
-- * No self-invitation (CHECK), no invitation of an older account (trigger),
--   and the code must belong to the inviter (composite FK).
-- * An invitation QUALIFIES (`qualify_referrals`) only when the invitee has a
--   confirmed account, entered a monthly contest, sent a valid prediction and
--   that prediction was graded on a decided fixture.
-- * Suspicious invitations are HELD, never paid automatically: a shared
--   network or install with another invitee of the same inviter, the
--   inviter's own install, or a burst of claims. A signal alone never
--   rejects; an admin approves or rejects (`review_referral`).
-- * A payment is ONE `referral_qualified` event in `gamification.events`
--   with dedupe_key `referral_qualified:<invitee_id>`: the existing UNIQUE
--   constraint makes a second payment for the same invitee impossible, and
--   the table is append-only, so a mistake is corrected by a compensating
--   `referral_revoked` event.
-- * Invitation points are NOT prediction points: nothing here touches the
--   ledger or any points total. They only break ties.
-- * Monthly points (`referral_month_points`): qualified invitations of the
--   inviter whose qualification falls inside that monthly contest, capped at
--   20, so they start from zero every month. Season points
--   (`referral_season_points`): the sum of the capped monthly points over
--   the sporting season (September to August). The event history is kept
--   forever.
-- * Off until the owner switches it on:
--   update gamification.feature_flags set enabled = true
--    where flag_key = 'referrals';
--
-- Raw IP addresses and install ids are never stored: they are hashed here
-- with a random salt that only the database holds.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The switch.
-- ---------------------------------------------------------------------------
insert into gamification.feature_flags (flag_key, description, enabled)
values (
  'referrals',
  'Invitations: claims are accepted and qualified invitations are paid '
  'only while this flag is on.',
  false
)
on conflict (flag_key) do nothing;

-- ---------------------------------------------------------------------------
-- The salt. One row, server-only, never exposed.
-- ---------------------------------------------------------------------------
create table if not exists gamification.referral_salt (
  singleton boolean primary key default true,
  salt      text not null,
  constraint referral_salt_singleton check (singleton),
  constraint referral_salt_long check (length(salt) >= 32)
);

insert into gamification.referral_salt (singleton, salt)
values (true, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (singleton) do nothing;

create or replace function gamification.referral_hash(p_kind text, p_value text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_value is null or btrim(p_value) = '' then null
    else encode(
      sha256(convert_to(
        (select s.salt from gamification.referral_salt s) || '|' || p_kind
          || '|' || btrim(p_value),
        'UTF8')),
      'hex')
  end
$$;

-- ---------------------------------------------------------------------------
-- One fixed code per user.
-- ---------------------------------------------------------------------------
create table if not exists gamification.referral_codes (
  user_id    uuid primary key
    constraint referral_codes_user_id_fkey
      references identity.users (id) on delete cascade,
  code       text not null,
  created_at timestamptz not null default now(),
  constraint referral_codes_code_uniq unique (code),
  constraint referral_codes_user_code_uniq unique (user_id, code),
  -- Upper-case letters and digits without the look-alikes 0 O 1 I L, the
  -- alphabet of the group invite codes (domain InviteCode).
  constraint referral_codes_code_shape
    check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$')
);

comment on table gamification.referral_codes is
  'One fixed invitation code per user (0073). Never updated or deleted.';

-- ---------------------------------------------------------------------------
-- Who invited whom. One row per invitee, forever.
-- ---------------------------------------------------------------------------
create table if not exists gamification.referrals (
  invitee_id   uuid primary key
    constraint referrals_invitee_id_fkey
      references identity.users (id) on delete cascade,
  referrer_id  uuid not null,
  code         text not null,
  claimed_at   timestamptz not null,
  ip_hash      text,
  install_hash text,
  constraint referrals_no_self check (invitee_id <> referrer_id),
  constraint referrals_code_fkey
    foreign key (referrer_id, code)
    references gamification.referral_codes (user_id, code)
);

comment on table gamification.referrals is
  'Who invited whom (0073). invitee_id is the primary key: one inviter per '
  'invitee, and the row can never be updated or deleted.';

create index if not exists referrals_referrer_claimed_idx
  on gamification.referrals (referrer_id, claimed_at);
create index if not exists referrals_ip_hash_idx
  on gamification.referrals (ip_hash) where ip_hash is not null;
create index if not exists referrals_install_hash_idx
  on gamification.referrals (install_hash) where install_hash is not null;

-- ---------------------------------------------------------------------------
-- Install hashes an inviter was seen with, so an invitee on the inviter's
-- own install can be held. Append-only like the rest.
-- ---------------------------------------------------------------------------
create table if not exists gamification.referral_install_marks (
  user_id      uuid not null
    constraint referral_install_marks_user_id_fkey
      references identity.users (id) on delete cascade,
  install_hash text not null,
  seen_at      timestamptz not null default now(),
  constraint referral_install_marks_pkey primary key (user_id, install_hash)
);

-- ---------------------------------------------------------------------------
-- Append-only backstops.
-- ---------------------------------------------------------------------------
create or replace function gamification.reject_referral_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only: % is forbidden', tg_table_name, tg_op
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists referral_codes_reject_mutation
  on gamification.referral_codes;
create trigger referral_codes_reject_mutation
  before update or delete on gamification.referral_codes
  for each row execute function gamification.reject_referral_mutation();

drop trigger if exists referrals_reject_mutation on gamification.referrals;
create trigger referrals_reject_mutation
  before update or delete on gamification.referrals
  for each row execute function gamification.reject_referral_mutation();

drop trigger if exists referral_install_marks_reject_mutation
  on gamification.referral_install_marks;
create trigger referral_install_marks_reject_mutation
  before update or delete on gamification.referral_install_marks
  for each row execute function gamification.reject_referral_mutation();

-- A claim belongs to a NEW account, and the inviter must be older than it.
create or replace function gamification.guard_referral_claim()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_invitee_created timestamptz;
  v_referrer_created timestamptz;
begin
  select u.created_at into v_invitee_created
    from identity.users u where u.id = new.invitee_id;
  select u.created_at into v_referrer_created
    from identity.users u where u.id = new.referrer_id;
  if v_invitee_created is null or v_referrer_created is null then
    raise exception 'referral: unknown user' using errcode = 'foreign_key_violation';
  end if;
  if new.claimed_at > v_invitee_created + interval '24 hours' then
    raise exception 'referral: the claim window of this account is closed'
      using errcode = 'check_violation';
  end if;
  if v_referrer_created >= v_invitee_created then
    raise exception 'referral: the inviter must be older than the invitee'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists referrals_guard_claim on gamification.referrals;
create trigger referrals_guard_claim
  before insert on gamification.referrals
  for each row execute function gamification.guard_referral_claim();

-- Every referral_* event must name a real invitation of that inviter, carry
-- the canonical dedupe key, and follow the life cycle.
create or replace function gamification.guard_referral_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.event_type not like 'referral\_%' then
    return new;
  end if;
  if new.event_type not in (
    'referral_held', 'referral_qualified', 'referral_rejected',
    'referral_revoked'
  ) then
    raise exception 'referral: unknown event type %', new.event_type
      using errcode = 'check_violation';
  end if;
  if new.ref_type is distinct from 'user' or new.ref_id is null then
    raise exception 'referral: the event must reference the invitee'
      using errcode = 'check_violation';
  end if;
  if new.dedupe_key <> new.event_type || ':' || new.ref_id::text then
    raise exception 'referral: dedupe_key must be <event_type>:<invitee_id>'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from gamification.referrals r
     where r.invitee_id = new.ref_id and r.referrer_id = new.user_id
  ) then
    raise exception 'referral: no such invitation for this inviter'
      using errcode = 'check_violation';
  end if;
  if new.event_type = 'referral_qualified' and exists (
    select 1 from gamification.events e
     where e.ref_id = new.ref_id and e.event_type = 'referral_rejected'
  ) then
    raise exception 'referral: a rejected invitation cannot be paid'
      using errcode = 'check_violation';
  end if;
  if new.event_type = 'referral_rejected' and exists (
    select 1 from gamification.events e
     where e.ref_id = new.ref_id and e.event_type = 'referral_qualified'
  ) then
    raise exception 'referral: a paid invitation is revoked, not rejected'
      using errcode = 'check_violation';
  end if;
  if new.event_type = 'referral_revoked' and not exists (
    select 1 from gamification.events e
     where e.ref_id = new.ref_id and e.event_type = 'referral_qualified'
  ) then
    raise exception 'referral: only a paid invitation can be revoked'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists events_guard_referral on gamification.events;
create trigger events_guard_referral
  before insert on gamification.events
  for each row execute function gamification.guard_referral_event();

create index if not exists events_referral_ref_idx
  on gamification.events (ref_id, event_type)
  where event_type like 'referral\_%';

-- ---------------------------------------------------------------------------
-- ensure_referral_code: the caller's fixed code, created on first use.
-- ---------------------------------------------------------------------------
create or replace function gamification.ensure_referral_code(p_user uuid)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_code text;
  v_bytes bytea;
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  i int;
begin
  select c.code into v_code
    from gamification.referral_codes c where c.user_id = p_user;
  if v_code is not null then
    return v_code;
  end if;
  loop
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 31) + 1, 1);
    end loop;
    begin
      insert into gamification.referral_codes (user_id, code)
      values (p_user, v_code);
      return v_code;
    exception when unique_violation then
      -- Either this user got a code concurrently, or the code is taken.
      select c.code into v_code
        from gamification.referral_codes c where c.user_id = p_user;
      if v_code is not null then
        return v_code;
      end if;
    end;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- mark_referral_install: remembers an install the user was seen with.
-- ---------------------------------------------------------------------------
create or replace function gamification.mark_referral_install(
  p_user uuid,
  p_install_id text,
  p_now timestamptz default now()
)
returns void
language sql
set search_path = ''
as $$
  insert into gamification.referral_install_marks (user_id, install_hash, seen_at)
  select p_user, gamification.referral_hash('install', p_install_id), p_now
   where gamification.referral_hash('install', p_install_id) is not null
  on conflict (user_id, install_hash) do nothing
$$;

-- ---------------------------------------------------------------------------
-- claim_referral: the invitee names the inviter's code.
-- Returns one of: claimed | already_claimed | disabled | invalid_code |
-- unknown_code | self_referral | window_closed
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- qualify_referrals: pays (or holds) every invitation that became eligible.
-- Safe to re-run: the events' UNIQUE dedupe_key makes a repeat a no-op.
-- Returns the number of events written.
-- ---------------------------------------------------------------------------
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
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- review_referral: an admin decides a held invitation, or revokes a paid one.
-- p_decision: approve | reject | revoke. The reason is mandatory.
-- Returns: approved | rejected | revoked | not_held | not_paid |
--          already_decided | unknown_invitation | reason_required |
--          invalid_decision
-- ---------------------------------------------------------------------------
create or replace function gamification.review_referral(
  p_invitee uuid,
  p_decision text,
  p_admin uuid,
  p_reason text,
  p_now timestamptz default now()
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_referrer uuid;
  v_held boolean;
  v_paid boolean;
  v_closed boolean;
  v_payload jsonb;
begin
  if p_decision not in ('approve', 'reject', 'revoke') then
    return 'invalid_decision';
  end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    return 'reason_required';
  end if;
  select r.referrer_id into v_referrer
    from gamification.referrals r where r.invitee_id = p_invitee;
  if v_referrer is null then
    return 'unknown_invitation';
  end if;
  select
    bool_or(e.event_type = 'referral_held'),
    bool_or(e.event_type = 'referral_qualified'),
    bool_or(e.event_type in ('referral_rejected', 'referral_revoked'))
    into v_held, v_paid, v_closed
    from gamification.events e
   where e.ref_id = p_invitee and e.event_type like 'referral\_%';
  v_held := coalesce(v_held, false);
  v_paid := coalesce(v_paid, false);
  v_closed := coalesce(v_closed, false);
  v_payload := jsonb_build_object(
    'invitee_id', p_invitee, 'reviewed_by', p_admin,
    'reason', btrim(p_reason));

  if p_decision = 'revoke' then
    if not v_paid then
      return 'not_paid';
    end if;
    if v_closed then
      return 'already_decided';
    end if;
    insert into gamification.events
      (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
       rule_version, occurred_at)
    values (gen_random_uuid(), v_referrer, 'referral_revoked', v_payload,
            'user', p_invitee, 'referral_revoked:' || p_invitee::text, 1, p_now)
    on conflict (dedupe_key) do nothing;
    return 'revoked';
  end if;

  if not v_held then
    return 'not_held';
  end if;
  if v_paid or v_closed then
    return 'already_decided';
  end if;
  insert into gamification.events
    (id, user_id, event_type, payload, ref_type, ref_id, dedupe_key,
     rule_version, occurred_at)
  values (
    gen_random_uuid(), v_referrer,
    case p_decision when 'approve' then 'referral_qualified'
                    else 'referral_rejected' end,
    v_payload, 'user', p_invitee,
    case p_decision when 'approve' then 'referral_qualified:'
                    else 'referral_rejected:' end || p_invitee::text,
    1, p_now)
  on conflict (dedupe_key) do nothing;
  return case p_decision when 'approve' then 'approved' else 'rejected' end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Points. Paid and not revoked, counted in the monthly contest whose window
-- holds the payment, capped at 20 per month.
-- ---------------------------------------------------------------------------
create or replace view gamification.referral_month_points as
  with months as (
    select s.id as season_id, s.label, s.start_at, s.end_at
      from competition.seasons s
     where length(s.label) = 7 and s.label ~ '^[0-9]{2}/[0-9]{4}$'
  ),
  paid as (
    select q.user_id, q.ref_id as invitee_id, q.occurred_at
      from gamification.events q
     where q.event_type = 'referral_qualified'
       and not exists (
         select 1 from gamification.events r
          where r.event_type = 'referral_revoked'
            and r.ref_id = q.ref_id
       )
  )
  select m.season_id,
         m.label,
         p.user_id,
         least(count(*), 20)::integer as referral_points,
         count(*)::integer as qualified_count
    from paid p
    join months m
      on p.occurred_at >= m.start_at
     and p.occurred_at <  m.end_at
   group by m.season_id, m.label, p.user_id;

comment on view gamification.referral_month_points is
  'Invitation points per user per monthly contest (0073): paid, not revoked, '
  'capped at 20. Tie-break only; never added to prediction points.';

-- The sporting season runs September to August; its key is the year it
-- starts in (09/2026 .. 08/2027 -> 2026), the rule GET /leaderboard/season
-- applies to month labels.
create or replace view gamification.referral_season_points as
  select case when substr(m.label, 1, 2)::int >= 9
              then substr(m.label, 4, 4)::int
              else substr(m.label, 4, 4)::int - 1 end as season_start_year,
         m.user_id,
         sum(m.referral_points)::integer as referral_points,
         sum(m.qualified_count)::integer as qualified_count
    from gamification.referral_month_points m
   group by 1, m.user_id;

comment on view gamification.referral_season_points is
  'Invitation points per user per sporting season (0073): the sum of the '
  'capped monthly points. Tie-break only.';

-- ---------------------------------------------------------------------------
-- Server-only surface: the client reads nothing here directly.
-- ---------------------------------------------------------------------------
alter table gamification.referral_salt enable row level security;
alter table gamification.referral_codes enable row level security;
alter table gamification.referrals enable row level security;
alter table gamification.referral_install_marks enable row level security;

revoke all on gamification.referral_salt from anon, authenticated;
revoke all on gamification.referral_codes from anon, authenticated;
revoke all on gamification.referrals from anon, authenticated;
revoke all on gamification.referral_install_marks from anon, authenticated;
revoke all on gamification.referral_month_points from anon, authenticated;
revoke all on gamification.referral_season_points from anon, authenticated;
revoke execute on function gamification.referral_hash(text, text) from public, anon, authenticated;
revoke execute on function gamification.ensure_referral_code(uuid) from public, anon, authenticated;
revoke execute on function gamification.mark_referral_install(uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function gamification.claim_referral(uuid, text, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function gamification.qualify_referrals(timestamptz) from public, anon, authenticated;
revoke execute on function gamification.review_referral(uuid, text, uuid, text, timestamptz) from public, anon, authenticated;

commit;
