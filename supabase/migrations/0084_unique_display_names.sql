-- ============================================================================
-- Migration 0084: one display name per player
--
-- ADDITIVE ONLY. Two functions, one trigger function, one trigger, one index;
-- no existing row is touched -- names that are ALREADY shared stay as they
-- are until an admin renames one of them (Admin -> Users -> duplicate names).
--
-- Why: nothing stopped two players from choosing the same display name, so
-- the boards could show two "Ahmed" rows nobody could tell apart.
--
-- Two names are the same when their identity.display_name_key matches:
-- letter case, whitespace, Arabic diacritics, tatweel and invisible
-- direction marks are ignored, and the Arabic letter variants that read the
-- same are folded (alef forms -> alef, alef maqsura -> ya, ta marbuta -> ha,
-- Persian ya/kaf -> Arabic ya/kaf). Decided 2026-10-02 by the owner.
--
-- A player who still carries the automatic name (the part of the e-mail
-- before '@', or 'Player') is never counted: that name is temporary, and two
-- addresses can share it. The app sends such a player to the name screen.
--
-- On UPDATE a taken name is refused (unique_violation, constraint
-- users_display_name_taken), which PostgresUserDirectory maps to
-- identity.display_name_taken. On INSERT -- the first sign-in after sign-up,
-- carrying the name typed at registration -- a taken name falls back to the
-- automatic one instead of failing the sign-in, so the player lands on the
-- name screen and picks another. An advisory lock per name key serialises
-- two players claiming the same name at the same moment.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function identity.display_name_key(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  -- Escapes, not literal characters: the marks are invisible and a copy
  -- and paste could drop them.
  select nullif(
    regexp_replace(
      translate(
        lower(
          regexp_replace(
            coalesce(p_name, ''),
            '[\u064B-\u0652\u0670\u0640\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
            '',
            'g'
          )
        ),
        'أإآٱىةیک',
        'اااايهيك'
      ),
      '\s+',
      '',
      'g'
    ),
    ''
  )
$$;

comment on function identity.display_name_key(text) is
  'The comparison key of a display name (0084): case, whitespace, diacritics, '
  'tatweel and direction marks dropped; alef forms, alef maqsura, ta marbuta '
  'and Persian ya/kaf folded. Two names with one key are the same name.';

create or replace function identity.automatic_display_name(p_email text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(nullif(split_part(coalesce(p_email, ''), '@', 1), ''), 'Player')
$$;

comment on function identity.automatic_display_name(text) is
  'The temporary name an account carries until its owner chooses one: the '
  'e-mail local part, or Player (mirrors User.automaticDisplayName, 0084).';

create or replace function identity.guard_unique_display_name()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
begin
  if new.display_name is null
     or new.display_name = identity.automatic_display_name(new.email) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.display_name is not distinct from old.display_name then
    return new;
  end if;

  v_key := identity.display_name_key(new.display_name);
  if v_key is null then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('display_name:' || v_key, 0));

  if exists (
    select 1
      from identity.users u
     where u.id <> new.id
       and u.display_name is not null
       and u.display_name <> identity.automatic_display_name(u.email)
       and identity.display_name_key(u.display_name) = v_key
  ) then
    if tg_op = 'INSERT' then
      new.display_name := identity.automatic_display_name(new.email);
      return new;
    end if;
    raise exception 'display name % is already taken', new.display_name
      using errcode = 'unique_violation',
            constraint = 'users_display_name_taken';
  end if;

  return new;
end;
$$;

comment on function identity.guard_unique_display_name() is
  'Keeps display names unique by identity.display_name_key (0084): refuses a '
  'taken name on update, and replaces it with the automatic name on insert.';

drop trigger if exists users_unique_display_name on identity.users;
create trigger users_unique_display_name
  before insert or update of display_name on identity.users
  for each row execute function identity.guard_unique_display_name();

create index if not exists users_display_name_key_idx
  on identity.users (identity.display_name_key(display_name));

insert into ops.applied_migrations (version)
values ('0084_unique_display_names')
on conflict (version) do nothing;

commit;
