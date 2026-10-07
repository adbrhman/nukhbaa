-- ============================================================================
-- Migration 0097: invite a player to a friends' league by name (2026-10-07)
--
-- A member of a league (a group, 0007) finds a player by name and invites
-- them; the player is told in the inbox and by push, and accepts (joins the
-- league) or declines. The invite link stays as it was.
--
--   * "group".group_invitations -- one invitation per (league, player):
--     who invited, pending until the player accepts or declines. A player
--     is never invited to the same league twice, so a declined invitation
--     is not repeated.
--   * notification.notification_kind gains 'group_invited'. The row
--     reuses the existing group_id and actor_user_id columns (the league and
--     who invited), like 'group_member_joined'.
--
-- Server-only, like 0090: row level security on, nothing granted to anon
-- or authenticated.
--
-- ALTER TYPE ... ADD VALUE is safe in this transaction: nothing below uses
-- the new value; only application code that runs afterward does.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

create table if not exists "group".group_invitations (
  id              uuid        primary key,
  group_id        uuid        not null,
  inviter_user_id uuid        not null,
  invitee_user_id uuid        not null,
  status          text        not null default 'pending',
  created_at      timestamptz not null default now(),
  responded_at    timestamptz,
  constraint group_invitations_group_id_fkey
    foreign key (group_id) references "group".groups (id) on delete cascade,
  constraint group_invitations_inviter_fkey
    foreign key (inviter_user_id) references identity.users (id)
    on delete cascade,
  constraint group_invitations_invitee_fkey
    foreign key (invitee_user_id) references identity.users (id)
    on delete cascade,
  constraint group_invitations_status_check
    check (status in ('pending', 'accepted', 'declined')),
  constraint group_invitations_not_self
    check (inviter_user_id <> invitee_user_id),
  constraint group_invitations_responded_check
    check ((status = 'pending') = (responded_at is null)),
  constraint group_invitations_once unique (group_id, invitee_user_id)
);

comment on table "group".group_invitations is
  'One invitation per (league, player) to a friends'' league, pending until '
  'the player accepts (joins) or declines (0097).';

create index if not exists group_invitations_invitee_idx
  on "group".group_invitations (invitee_user_id, created_at desc);

alter table "group".group_invitations enable row level security;
revoke all on "group".group_invitations from public, anon, authenticated;

alter type notification.notification_kind add value if not exists 'group_invited';

insert into ops.applied_migrations (version)
values ('0097_group_invitations')
on conflict (version) do nothing;

commit;
