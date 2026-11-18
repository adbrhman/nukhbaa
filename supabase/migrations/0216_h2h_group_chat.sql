-- ============================================================================
-- Migration 0216: a chat for each head-to-head group (script 280)
--
-- The owner's request (2026-11-15): every group of the head-to-head league
-- gets a chat where the members of that group, and only they, write to each
-- other. The groups change every month (promotion and relegation), and so
-- does the chat: it belongs to the group of one month (gamification.
-- h2h_leagues.id). The members of next month's group write in next month's
-- chat; the old chat stays readable for the players who sat in it.
--
--   chat.h2h_messages       one row per message of a group: sender, text
--                           (1 to 500 characters), when an admin hid it.
--   chat.h2h_reads          the last message each member has read (unread
--                           badge).
--   chat.muted_users        players an admin barred from writing.
--   chat.rules_acceptances  who accepted the chat rules, and which version.
--
-- Who may write is a database fact, not an application promise. A BEFORE
-- INSERT guard on chat.h2h_messages refuses a message when the sender
--   - holds no seat in the group (h2h_messages_member_only);
--   - already sits in a group of a LATER month: the old chat is read-only
--     (h2h_messages_group_closed);
--   - is muted (h2h_messages_sender_muted);
--   - has not accepted the chat rules (h2h_messages_rules_not_accepted).
-- Reading is the server's job (it lists only the groups the caller sits in).
--
-- Reporting and blocking are not here: they are script 225's system (a report
-- reaches the owner through the player's support chat, 0187; a block is kept
-- on the phone), and the chat uses it as it is.
--
-- A player who deletes his account (0178) loses his messages, reads, mute and
-- rules acceptance: a trigger on identity.users.deleted_at.
--
-- Server-only, like the support chat (0187): RLS on, no policy, nothing
-- granted to anon or authenticated.
--
-- ADDITIVE ONLY. No existing row is touched. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists chat;

comment on schema chat is
  'The chat of each head-to-head group, with its blocks, reports and mutes '
  '(0216). Server-only.';

revoke all on schema chat from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
create table if not exists chat.h2h_messages (
  id         bigint      generated always as identity primary key,
  league_id  uuid        not null
    constraint h2h_messages_league_id_fkey
      references gamification.h2h_leagues (id),
  sender_id  uuid        not null
    constraint h2h_messages_sender_id_fkey
      references identity.users (id) on delete cascade,
  body       text        not null,
  -- Set when an admin hides the message (report handled): it stays in the
  -- table as evidence and is never listed to the players.
  hidden_at  timestamptz,
  hidden_by  uuid
    constraint h2h_messages_hidden_by_fkey
      references identity.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint h2h_messages_body_check
    check (length(body) between 1 and 500 and body = btrim(body))
);

comment on table chat.h2h_messages is
  'One message of a head-to-head group chat (0216), oldest first by id. '
  'hidden_at: hidden by an admin, kept as evidence.';

create index if not exists h2h_messages_league_idx
  on chat.h2h_messages (league_id, id desc);

create index if not exists h2h_messages_sender_idx
  on chat.h2h_messages (sender_id);

-- ---------------------------------------------------------------------------
-- Reads (the unread badge)
-- ---------------------------------------------------------------------------
create table if not exists chat.h2h_reads (
  league_id    uuid        not null
    constraint h2h_reads_league_id_fkey
      references gamification.h2h_leagues (id),
  user_id      uuid        not null
    constraint h2h_reads_user_id_fkey
      references identity.users (id) on delete cascade,
  last_read_id bigint      not null default 0,
  updated_at   timestamptz not null default now(),
  constraint h2h_reads_pkey primary key (league_id, user_id),
  constraint h2h_reads_last_read_nonneg check (last_read_id >= 0)
);

comment on table chat.h2h_reads is
  'The newest message of a group chat a member has read (0216).';

-- ---------------------------------------------------------------------------
-- Mutes and the chat rules
-- ---------------------------------------------------------------------------
create table if not exists chat.muted_users (
  user_id    uuid        primary key
    constraint muted_users_user_id_fkey
      references identity.users (id) on delete cascade,
  muted_by   uuid
    constraint muted_users_muted_by_fkey
      references identity.users (id) on delete set null,
  reason     text,
  created_at timestamptz not null default now()
);

comment on table chat.muted_users is
  'Players an admin barred from writing in the chats (0216).';

create table if not exists chat.rules_acceptances (
  user_id     uuid        primary key
    constraint rules_acceptances_user_id_fkey
      references identity.users (id) on delete cascade,
  version     smallint    not null default 1,
  accepted_at timestamptz not null default now(),
  constraint rules_acceptances_version_positive check (version > 0)
);

comment on table chat.rules_acceptances is
  'Who accepted the chat rules, and which version of them (0216).';

alter table chat.h2h_messages     enable row level security;
alter table chat.h2h_reads        enable row level security;
alter table chat.muted_users      enable row level security;
alter table chat.rules_acceptances enable row level security;

revoke all on chat.h2h_messages      from anon, authenticated;
revoke all on chat.h2h_reads         from anon, authenticated;
revoke all on chat.muted_users       from anon, authenticated;
revoke all on chat.rules_acceptances from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Who may write: the backstop in the database
-- ---------------------------------------------------------------------------
create or replace function chat.check_h2h_message()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month date;
begin
  select m.month_start
    into v_month
    from gamification.h2h_league_members m
   where m.league_id = new.league_id
     and m.user_id = new.sender_id;
  if v_month is null then
    raise exception 'chat: player % holds no seat in group %',
      new.sender_id, new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_messages_member_only';
  end if;

  -- A newer month has seated the sender elsewhere: this chat is over.
  if exists (select 1
               from gamification.h2h_league_members m2
              where m2.user_id = new.sender_id
                and m2.month_start > v_month) then
    raise exception 'chat: the group % of % is closed to player %',
      new.league_id, v_month, new.sender_id
      using errcode = 'check_violation',
            constraint = 'h2h_messages_group_closed';
  end if;

  if exists (select 1 from chat.muted_users u
              where u.user_id = new.sender_id) then
    raise exception 'chat: player % is muted', new.sender_id
      using errcode = 'check_violation',
            constraint = 'h2h_messages_sender_muted';
  end if;

  if not exists (select 1 from chat.rules_acceptances r
                  where r.user_id = new.sender_id) then
    raise exception 'chat: player % has not accepted the rules',
      new.sender_id
      using errcode = 'check_violation',
            constraint = 'h2h_messages_rules_not_accepted';
  end if;

  return new;
end;
$$;

comment on function chat.check_h2h_message() is
  'Backstop of the group chat (0216): the sender holds a seat in the group, '
  'is not seated in a later month, is not muted and accepted the rules.';

revoke all on function chat.check_h2h_message()
  from public, anon, authenticated;

drop trigger if exists h2h_messages_check on chat.h2h_messages;
create trigger h2h_messages_check
  before insert on chat.h2h_messages
  for each row
  execute function chat.check_h2h_message();

-- ---------------------------------------------------------------------------
-- A deleted account (0178) takes its chat data with it
-- ---------------------------------------------------------------------------
create or replace function chat.forget_deleted_player()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from chat.h2h_messages     where sender_id   = new.id;
    delete from chat.h2h_reads        where user_id     = new.id;
    delete from chat.muted_users      where user_id     = new.id;
    delete from chat.rules_acceptances where user_id    = new.id;
  end if;
  return new;
end;
$$;

comment on function chat.forget_deleted_player() is
  'Removes the chat data of an account when it is deleted (0216, after '
  '0178).';

revoke all on function chat.forget_deleted_player()
  from public, anon, authenticated;

drop trigger if exists users_forget_group_chat on identity.users;
create trigger users_forget_group_chat
  after update of deleted_at on identity.users
  for each row
  execute function chat.forget_deleted_player();

insert into ops.applied_migrations (version)
values ('0216_h2h_group_chat')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0216_h2h_group_chat';                          -- 1 row
-- select relname, relrowsecurity from pg_class
--  where relnamespace = 'chat'::regnamespace and relkind = 'r'
--  order by relname;                                   -- 4 rows, all true
-- select tgname from pg_trigger
--  where tgname in ('h2h_messages_check', 'users_forget_group_chat')
--    and not tgisinternal;                                          -- 2 rows
