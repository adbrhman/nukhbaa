-- Migration 0090 - Duel foundation.
-- Additive only. Duel state is separate from referrals and monthly ranking.
-- Stored challenge states are only open/cancelled/declined. Accepted/active,
-- expired/settled/draw and winner/points are derived from rows and time.

begin;

create schema if not exists social;

-- Crockford-like alphabet without I, L, O, U, 0 or 1. Twelve characters
-- provide a large non-guessable space while staying easy to read aloud.
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'duel_challenge_status' and n.nspname = 'social'
  ) then
    create type social.duel_challenge_status as enum ('open', 'cancelled', 'declined');
  end if;
end
$$;

create table if not exists social.duel_challenges (
  id                         uuid primary key default gen_random_uuid(),
  code                       text not null,
  season_id                  uuid not null
                             references competition.seasons (id) on delete restrict,
  fixture_id                 uuid not null
                             references football_data.fixtures (id) on delete restrict,
  challenger_participant_id  uuid not null
                             references competition.participants (id) on delete restrict,
  target_user_id             uuid
                             references identity.users (id) on delete restrict,
  capacity                   smallint not null default 5,
  status                     social.duel_challenge_status not null default 'open',
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  constraint duel_challenges_code_uniq unique (code),
  constraint duel_challenges_code_shape
    check (code ~ '^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{12}$'),
  constraint duel_challenges_capacity_range
    check (capacity between 1 and 10),
  constraint duel_challenges_private_capacity
    check (target_user_id is null or capacity = 1)
);

comment on table social.duel_challenges is
  'A shareable duel invitation for one fixture. The challenge is separate '
  'from referrals and monthly ranking. Only open/cancelled/declined are '
  'stored; acceptance and expiry are derived from duels and kickoff time.';

comment on column social.duel_challenges.target_user_id is
  'Optional target account for a private duel. A non-null target fixes '
  'capacity to one; display-name uniqueness is enforced by identity 0084.';

comment on column social.duel_challenges.capacity is
  'Maximum accepted duels from this challenge: 1 for private, up to 10 for open. '
  'Product default is 5; DuelPolicy in the application must mirror that value.';

create index if not exists duel_challenges_challenger_idx
  on social.duel_challenges (challenger_participant_id, status);
create index if not exists duel_challenges_fixture_idx
  on social.duel_challenges (fixture_id, status);
create index if not exists duel_challenges_target_idx
  on social.duel_challenges (target_user_id, status)
  where target_user_id is not null;

drop trigger if exists duel_challenges_set_updated_at on social.duel_challenges;
create trigger duel_challenges_set_updated_at
  before update on social.duel_challenges
  for each row execute function identity.set_updated_at();

create table if not exists social.duels (
  id                         uuid primary key default gen_random_uuid(),
  challenge_id               uuid not null
                             references social.duel_challenges (id) on delete restrict,
  fixture_id                 uuid not null
                             references football_data.fixtures (id) on delete restrict,
  challenger_participant_id  uuid not null
                             references competition.participants (id) on delete restrict,
  opponent_participant_id    uuid not null
                             references competition.participants (id) on delete restrict,
  accepted_at                timestamptz not null default now(),
  created_at                 timestamptz not null default now(),
  constraint duels_distinct_participants
    check (challenger_participant_id <> opponent_participant_id),
  constraint duels_challenge_opponent_uniq
    unique (challenge_id, opponent_participant_id)
);

comment on table social.duels is
  'One accepted confrontation. It stores identity and fixture only. No '
  'winner, points, settled state or copied prediction is stored; those are '
  'derived from prediction.fixture_predictions, scoring.fixture_scores and time.';

create unique index if not exists duels_fixture_pair_uniq
  on social.duels (
    fixture_id,
    least(challenger_participant_id, opponent_participant_id),
    greatest(challenger_participant_id, opponent_participant_id)
  );

create index if not exists duels_challenger_idx
  on social.duels (challenger_participant_id, fixture_id);
create index if not exists duels_opponent_idx
  on social.duels (opponent_participant_id, fixture_id);
create index if not exists duels_challenge_idx
  on social.duels (challenge_id, accepted_at);

-- Identity fields of a challenge are immutable. Only lifecycle fields may
-- change, and lifecycle can move away from open but never back to open.
create or replace function social.guard_duel_challenge_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.code is distinct from old.code
     or new.season_id is distinct from old.season_id
     or new.fixture_id is distinct from old.fixture_id
     or new.challenger_participant_id is distinct from old.challenger_participant_id
     or new.target_user_id is distinct from old.target_user_id
     or new.capacity is distinct from old.capacity
     or new.created_at is distinct from old.created_at then
    raise exception 'duel challenge identity is immutable'
      using errcode = 'check_violation',
            constraint = 'duel_challenges_identity_immutable';
  end if;
  if old.status <> 'open' and new.status <> old.status then
    raise exception 'closed duel challenge cannot change state'
      using errcode = 'check_violation',
            constraint = 'duel_challenges_status_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists duel_challenges_guard_change on social.duel_challenges;
create trigger duel_challenges_guard_change
  before update on social.duel_challenges
  for each row execute function social.guard_duel_challenge_change();

-- Generate the share code from cryptographic random bytes, never random().
create or replace function social.new_duel_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
  bytes bytea;
  code text;
  i integer;
begin
  bytes := gen_random_bytes(12);
  code := '';
  for i in 0..11 loop
    code := code || substr(alphabet, 1 + (get_byte(bytes, i) % 30), 1);
  end loop;
  return code;
end;
$$;

comment on function social.new_duel_code() is
  'Returns a 12-character cryptographically random duel code using an alphabet '
  'without visually ambiguous characters. Used only by the backend.';

-- Create is the DB backstop. The application must resolve the current season,
-- participant and target first; this function re-checks all integrity gates.
create or replace function social.create_duel_challenge(
  p_challenger_user_id uuid,
  p_season_id uuid,
  p_fixture_id uuid,
  p_capacity smallint default 5,
  p_target_user_id uuid default null,
  p_now timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_challenger_participant uuid;
  v_kickoff timestamptz;
  v_pending integer;
  v_id uuid;
  v_code text;
  v_attempt integer;
begin
  if p_capacity < 1 or p_capacity > 10 then
    raise exception 'duel capacity must be between 1 and 10'
      using errcode = 'check_violation',
            constraint = 'duel_challenges_capacity_range';
  end if;
  if p_target_user_id is not null and p_capacity <> 1 then
    raise exception 'private duel capacity must be one'
      using errcode = 'check_violation',
            constraint = 'duel_challenges_private_capacity';
  end if;
  if p_target_user_id = p_challenger_user_id then
    raise exception 'cannot duel yourself'
      using errcode = 'check_violation',
            constraint = 'duel_challenges_not_self';
  end if;

  select fs.kickoff_at
    into v_kickoff
    from competition.season_fixtures sf
    join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
   where sf.season_id = p_season_id
     and sf.fixture_id = p_fixture_id;
  if v_kickoff is null then
    raise exception 'fixture is not linked to the season'
      using errcode = 'check_violation',
            constraint = 'duel_fixture_not_in_season';
  end if;
  if v_kickoff <= p_now + interval '30 minutes' then
    raise exception 'duel must be created at least 30 minutes before kickoff'
      using errcode = 'check_violation',
            constraint = 'duel_minimum_lead_time';
  end if;

  select p.id
    into v_challenger_participant
    from competition.participants p
    join identity.users u on u.id = p.user_id
   where p.season_id = p_season_id
     and p.user_id = p_challenger_user_id
     and p.status = 'active'
     and u.status = 'active';
  if v_challenger_participant is null then
    raise exception 'challenger is not an active participant in the season'
      using errcode = 'check_violation',
            constraint = 'duel_challenger_not_participant';
  end if;

  if p_target_user_id is not null and not exists (
    select 1 from identity.users u
     where u.id = p_target_user_id and u.status = 'active'
  ) then
    raise exception 'target user is not active'
      using errcode = 'check_violation',
            constraint = 'duel_target_not_active';
  end if;

  -- Serialise the pending-count invariant per challenger. This closes the
  -- same race class as the daily-double and unique-display-name guards.
  perform pg_advisory_xact_lock(
    hashtextextended('duel_pending:' || p_challenger_user_id::text, 0)
  );

  select count(*)
    into v_pending
    from social.duel_challenges c
    join competition.participants cp
      on cp.id = c.challenger_participant_id
    join competition.fixture_schedules fs
      on fs.fixture_id = c.fixture_id
   where c.status = 'open'
     and cp.user_id = p_challenger_user_id
     and fs.kickoff_at > p_now
     and (
       select count(*) from social.duels d where d.challenge_id = c.id
     ) < c.capacity;
  if v_pending >= 10 then
    raise exception 'maximum of 10 pending duel challenges reached'
      using errcode = 'check_violation',
            constraint = 'duel_max_pending_challenges';
  end if;

  for v_attempt in 1..5 loop
    v_code := social.new_duel_code();
    begin
      insert into social.duel_challenges (
        code,
        season_id,
        fixture_id,
        challenger_participant_id,
        target_user_id,
        capacity
      ) values (
        v_code,
        p_season_id,
        p_fixture_id,
        v_challenger_participant,
        p_target_user_id,
        p_capacity
      ) returning id into v_id;
      return v_id;
    exception when unique_violation then
      if v_attempt = 5 then
        raise;
      end if;
    end;
  end loop;

  raise exception 'unable to allocate duel code';
end;
$$;

-- Accept is deliberately prediction-aware. The application calls
-- SubmitFixturePrediction first and then this function inside the SAME DB
-- transaction. The function re-checks both rows, so a duel can never be
-- accepted without both predictions. It never copies those predictions.
create or replace function social.accept_duel_challenge(
  p_challenge_id uuid,
  p_opponent_user_id uuid,
  p_now timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c social.duel_challenges%rowtype;
  v_kickoff timestamptz;
  v_challenger_user uuid;
  v_challenger_participant uuid;
  v_opponent_participant uuid;
  v_existing integer;
  v_id uuid;
begin
  select * into c
    from social.duel_challenges
   where id = p_challenge_id
   for update;
  if not found then
    raise exception 'duel challenge not found'
      using errcode = 'check_violation', constraint = 'duel_not_found';
  end if;
  if c.status <> 'open' then
    raise exception 'duel challenge is not open'
      using errcode = 'check_violation', constraint = 'duel_not_open';
  end if;

  select fs.kickoff_at into v_kickoff
    from competition.fixture_schedules fs
   where fs.fixture_id = c.fixture_id;
  if v_kickoff is null or p_now >= v_kickoff then
    raise exception 'duel challenge expired at kickoff'
      using errcode = 'check_violation', constraint = 'duel_expired';
  end if;

  select p.user_id, p.id
    into v_challenger_user, v_challenger_participant
    from competition.participants p
    join identity.users u on u.id = p.user_id
   where p.id = c.challenger_participant_id
     and p.season_id = c.season_id
     and p.status = 'active'
     and u.status = 'active';
  if v_challenger_participant is null then
    raise exception 'challenger is no longer active'
      using errcode = 'check_violation', constraint = 'duel_challenger_inactive';
  end if;
  if v_challenger_user = p_opponent_user_id then
    raise exception 'cannot duel yourself'
      using errcode = 'check_violation', constraint = 'duel_challenger_self';
  end if;

  if c.target_user_id is not null and c.target_user_id <> p_opponent_user_id then
    raise exception 'this private duel is reserved for another user'
      using errcode = 'check_violation', constraint = 'duel_wrong_target';
  end if;

  select p.id
    into v_opponent_participant
    from competition.participants p
    join identity.users u on u.id = p.user_id
   where p.season_id = c.season_id
     and p.user_id = p_opponent_user_id
     and p.status = 'active'
     and u.status = 'active';
  if v_opponent_participant is null then
    raise exception 'opponent is not an active participant in the season'
      using errcode = 'check_violation',
            constraint = 'duel_opponent_not_participant';
  end if;

  select count(*) into v_existing
    from social.duels d
   where d.challenge_id = c.id;
  if v_existing >= c.capacity then
    raise exception 'duel challenge capacity is full'
      using errcode = 'check_violation', constraint = 'duel_capacity_full';
  end if;

  if exists (
    select 1 from social.duels d
     where d.fixture_id = c.fixture_id
       and least(d.challenger_participant_id, d.opponent_participant_id)
           = least(v_challenger_participant, v_opponent_participant)
       and greatest(d.challenger_participant_id, d.opponent_participant_id)
           = greatest(v_challenger_participant, v_opponent_participant)
  ) then
    raise exception 'this pair already has a duel for this fixture'
      using errcode = 'unique_violation', constraint = 'duel_pair_already_exists';
  end if;

  if not exists (
    select 1 from prediction.fixture_predictions fp
     where fp.fixture_id = c.fixture_id
       and fp.participant_id = v_challenger_participant
  ) then
    raise exception 'challenger must have a prediction before acceptance'
      using errcode = 'check_violation', constraint = 'duel_challenger_prediction_required';
  end if;
  if not exists (
    select 1 from prediction.fixture_predictions fp
     where fp.fixture_id = c.fixture_id
       and fp.participant_id = v_opponent_participant
  ) then
    raise exception 'opponent must have a prediction before acceptance'
      using errcode = 'check_violation', constraint = 'duel_opponent_prediction_required';
  end if;

  insert into social.duels (
    challenge_id,
    fixture_id,
    challenger_participant_id,
    opponent_participant_id
  ) values (
    c.id,
    c.fixture_id,
    v_challenger_participant,
    v_opponent_participant
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function social.cancel_duel_challenge(
  p_challenge_id uuid,
  p_challenger_user_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select c.id into v_id
    from social.duel_challenges c
    join competition.participants p on p.id = c.challenger_participant_id
   where c.id = p_challenge_id
     and p.user_id = p_challenger_user_id
     and c.status = 'open'
   for update;
  if v_id is null then
    raise exception 'duel challenge cannot be cancelled'
      using errcode = 'check_violation', constraint = 'duel_cancel_not_allowed';
  end if;
  update social.duel_challenges
     set status = 'cancelled'
   where id = v_id;
end;
$$;

create or replace function social.decline_duel_challenge(
  p_challenge_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select c.id into v_id
    from social.duel_challenges c
   where c.id = p_challenge_id
     and c.target_user_id = p_target_user_id
     and c.status = 'open'
     and not exists (select 1 from social.duels d where d.challenge_id = c.id)
   for update;
  if v_id is null then
    raise exception 'duel challenge cannot be declined'
      using errcode = 'check_violation', constraint = 'duel_decline_not_allowed';
  end if;
  update social.duel_challenges
     set status = 'declined'
   where id = v_id;
end;
$$;

-- A suspended account cannot leave an open challenge pointing at it. This is
-- a lifecycle backstop only; accepted duels are not rewritten here because
-- their outcome remains derived from the fixture and the participants' rows.
create or replace function social.cancel_open_duel_challenges_for_user()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'suspended' and old.status is distinct from new.status then
    update social.duel_challenges c
       set status = 'cancelled'
     where c.status = 'open'
       and (
         c.target_user_id = new.id
         or exists (
           select 1
             from competition.participants p
            where p.id = c.challenger_participant_id
              and p.user_id = new.id
         )
       );
  end if;
  return new;
end;
$$;

drop trigger if exists users_cancel_open_duel_challenges
  on identity.users;
create trigger users_cancel_open_duel_challenges
  after update of status on identity.users
  for each row execute function social.cancel_open_duel_challenges_for_user();

-- Backend-only surface. Client roles get neither table privileges nor function
-- execution; the backend database owner is the only writer in this phase.
alter table social.duel_challenges enable row level security;
alter table social.duels enable row level security;
revoke all on social.duel_challenges from public, anon, authenticated;
revoke all on social.duels from public, anon, authenticated;
revoke all on function social.new_duel_code() from public, anon, authenticated;
revoke all on function social.create_duel_challenge(uuid, uuid, uuid, smallint, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function social.accept_duel_challenge(uuid, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function social.cancel_duel_challenge(uuid, uuid)
  from public, anon, authenticated;
revoke all on function social.decline_duel_challenge(uuid, uuid)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0090_duels')
on conflict (version) do nothing;

commit;
