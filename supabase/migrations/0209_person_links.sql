-- ============================================================================
-- Migration 0209: one person's accounts, linked by the owner admin
--
-- ADDITIVE ONLY. One table and two functions; no existing row is removed.
-- Linking hides accounts (identity.users.hidden_at, 0207); unlinking shows
-- again only the accounts the link itself hid. Nothing about any account,
-- prediction or point is deleted.
--
-- Decided by the owner on 2026-11-12 (script 263): a person may play with
-- two accounts (the rules allow a second account), never more. When one
-- person is found behind several accounts (a close name, the same phone),
-- the owner admin alone links them: he names the main account and, if he
-- wants, a second one; both keep counting, and every other account of that
-- person is hidden from every board (the 0207 filter). The hidden accounts
-- still sign in and predict.
--
-- 1. identity.person_links: one row per linked account -- its person (the
--    main account's id), whether it counts, and whether the link hid it.
-- 2. identity.set_person(main, second, others, by): sets the person in one
--    transaction and answers 'ok', or why not: 'too_few' (under two
--    accounts), 'duplicate', 'unknown' (an id not on file) or 'taken' (an
--    account already linked to another person). Accounts that leave the
--    person, and an account that becomes counted, are shown again when the
--    link had hidden them.
-- 3. identity.unlink_person(main): removes the person, shows again what the
--    link hid; answers how many accounts were linked.
--
-- Server only (no grant to anon or authenticated). Safe to re-run.
-- ============================================================================

begin;

create table if not exists identity.person_links (
  user_id uuid primary key references identity.users (id) on delete cascade,
  person_id uuid not null references identity.users (id) on delete cascade,
  counted boolean not null,
  hidden_by_link boolean not null default false,
  linked_at timestamptz not null default now(),
  linked_by uuid references identity.users (id) on delete set null
);

comment on table identity.person_links is
  'One person''s accounts, linked by the owner admin (script 263): person_id is the main account; counted accounts (at most two) stay on the boards, the others are hidden (hidden_by_link when the link hid them).';

create index if not exists person_links_person_idx
  on identity.person_links (person_id);

alter table identity.person_links enable row level security;
revoke all on identity.person_links from anon, authenticated;

create or replace function identity.set_person(
  p_main uuid,
  p_second uuid,
  p_others uuid[],
  p_by uuid
) returns text
language plpgsql
as $$
declare
  v_members uuid[] := array[p_main]
    || case when p_second is null then '{}'::uuid[] else array[p_second] end
    || coalesce(p_others, '{}'::uuid[]);
begin
  if cardinality(v_members) < 2 then
    return 'too_few';
  end if;
  if (select count(distinct x) from unnest(v_members) x)
       <> cardinality(v_members) then
    return 'duplicate';
  end if;
  if (select count(*) from identity.users where id = any (v_members))
       <> cardinality(v_members) then
    return 'unknown';
  end if;
  if exists (
    select 1 from identity.person_links l
     where l.user_id = any (v_members) and l.person_id <> p_main
  ) or exists (
    select 1 from identity.person_links l
     where l.person_id = any (v_members) and l.person_id <> p_main
  ) then
    return 'taken';
  end if;

  -- Accounts leaving the person: shown again when the link hid them.
  update identity.users u
     set hidden_at = null, updated_at = now()
    from identity.person_links l
   where l.person_id = p_main
     and l.user_id = u.id
     and not (l.user_id = any (v_members))
     and l.hidden_by_link;
  delete from identity.person_links l
   where l.person_id = p_main
     and not (l.user_id = any (v_members));

  -- An account that becomes counted: shown again when the link hid it.
  update identity.users u
     set hidden_at = null, updated_at = now()
    from identity.person_links l
   where l.user_id = u.id
     and l.person_id = p_main
     and l.hidden_by_link
     and (u.id = p_main or u.id = p_second);

  insert into identity.person_links
    (user_id, person_id, counted, hidden_by_link, linked_at, linked_by)
  select m, p_main, (m = p_main or m is not distinct from p_second),
         false, now(), p_by
    from unnest(v_members) m
  on conflict (user_id) do update
     set counted = excluded.counted,
         hidden_by_link = case
           when excluded.counted then false
           else identity.person_links.hidden_by_link
         end,
         linked_by = excluded.linked_by;

  -- The others: hidden, unless already hidden (the owner's own hiding is
  -- kept as his, and is not undone by an unlink).
  update identity.person_links l
     set hidden_by_link = true
    from identity.users u
   where l.user_id = u.id
     and l.person_id = p_main
     and not l.counted
     and u.hidden_at is null;
  update identity.users u
     set hidden_at = now(), updated_at = now()
    from identity.person_links l
   where l.user_id = u.id
     and l.person_id = p_main
     and not l.counted
     and u.hidden_at is null;

  return 'ok';
end $$;

create or replace function identity.unlink_person(p_main uuid)
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  update identity.users u
     set hidden_at = null, updated_at = now()
    from identity.person_links l
   where l.person_id = p_main
     and l.user_id = u.id
     and l.hidden_by_link;
  delete from identity.person_links where person_id = p_main;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function identity.set_person(uuid, uuid, uuid[], uuid)
  from public, anon, authenticated;
revoke all on function identity.unlink_person(uuid)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0209_person_links')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0209_person_links';                               -- 1 row
-- select count(*) from identity.person_links;                         -- 0 at first
