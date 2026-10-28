-- ============================================================================
-- Migration 0187: a private chat between a player and Nukhbaa support
-- (script 165, 2026-10-28)
--
-- The owner's request (2026-10-28): a player writes to the developer from
-- inside the app and reads the answer there, with no WhatsApp and no
-- e-mail, so no phone number is ever shown. One conversation per player;
-- the other side is "دعم نُخبة", answered by any admin.
--
--   support.conversations  one row per player who ever wrote: status
--                          (open / closed / archived), the last message's
--                          time, preview and side, and an unread counter
--                          for each side.
--   support.messages       one row per message, oldest first by id: who
--                          sent it (the account, and its side at the time),
--                          the text, when it was read by the other side.
--
-- The support side is the admin role (identity.users.role = 'admin'), not
-- a separate account: every admin reads the same inbox, and the player
-- always sees one name, "دعم نُخبة". sender_id keeps which admin answered,
-- for the record; it never reaches the player.
--
-- A player who deletes his account (0178) loses his conversation: a trigger
-- on identity.users.deleted_at removes it, messages included.
--
-- notification.push_opens accepts two new push links: 'support' (the
-- player's chat) and 'support_inbox' (the admins' inbox).
--
-- Server-only: RLS on, no policy, nothing granted to anon or authenticated
-- (as 0070 did for ops.frame_reports).
--
-- ADDITIVE ONLY. No existing row is touched. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists support;

comment on schema support is
  'The private chat between a player and Nukhbaa support (0187). '
  'Server-only.';

revoke all on schema support from anon, authenticated;

create table if not exists support.conversations (
  id                   uuid        primary key default gen_random_uuid(),
  player_id            uuid        not null
    references identity.users (id) on delete cascade,
  status               text        not null default 'open',
  last_message_at      timestamptz,
  last_message_preview text,
  last_sender_role     text,
  player_unread        integer     not null default 0,
  support_unread       integer     not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint conversations_player_key unique (player_id),
  constraint conversations_status_check
    check (status in ('open', 'closed', 'archived')),
  constraint conversations_preview_check
    check (last_message_preview is null
           or length(last_message_preview) between 1 and 120),
  constraint conversations_last_sender_check
    check (last_sender_role is null
           or last_sender_role in ('player', 'support')),
  constraint conversations_unread_check
    check (player_unread >= 0 and support_unread >= 0)
);

comment on table support.conversations is
  'One conversation per player with Nukhbaa support (0187). player_unread: '
  'support messages the player has not read; support_unread: player '
  'messages no admin has read.';

create index if not exists conversations_last_message_idx
  on support.conversations (last_message_at desc, id);

create index if not exists conversations_support_unread_idx
  on support.conversations (last_message_at desc)
  where support_unread > 0;

create table if not exists support.messages (
  id              bigint      generated always as identity primary key,
  conversation_id uuid        not null
    references support.conversations (id) on delete cascade,
  sender_id       uuid
    references identity.users (id) on delete set null,
  sender_role     text        not null,
  body            text        not null,
  read_at         timestamptz,
  created_at      timestamptz not null default now(),
  constraint messages_sender_role_check
    check (sender_role in ('player', 'support')),
  constraint messages_body_check
    check (length(body) between 1 and 2000 and body = btrim(body))
);

comment on table support.messages is
  'One message of a support conversation (0187): its side at the time it '
  'was sent, the text, and when the other side read it.';

create index if not exists messages_conversation_idx
  on support.messages (conversation_id, id desc);

create index if not exists messages_unread_idx
  on support.messages (conversation_id, sender_role)
  where read_at is null;

alter table support.conversations enable row level security;
alter table support.messages enable row level security;
revoke all on support.conversations from anon, authenticated;
revoke all on support.messages from anon, authenticated;

-- A deleted account (0178) takes its conversation with it.
create or replace function support.forget_deleted_player()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from support.conversations c where c.player_id = new.id;
  end if;
  return new;
end;
$$;

comment on function support.forget_deleted_player() is
  'Removes the support conversation of an account when it is deleted '
  '(0187, after 0178).';

revoke all on function support.forget_deleted_player()
  from public, anon, authenticated;

drop trigger if exists users_forget_support_chat on identity.users;
create trigger users_forget_support_chat
  after update of deleted_at on identity.users
  for each row
  execute function support.forget_deleted_player();

-- The two new push links (0092 is the last to list them).
alter table notification.push_opens
  drop constraint if exists push_opens_link_check;
alter table notification.push_opens
  add constraint push_opens_link_check
    check (link in ('fixtures', 'league', 'inbox', 'duel',
                    'support', 'support_inbox'));

insert into ops.applied_migrations (version)
values ('0187_support_chat')
on conflict (version) do nothing;

commit;
