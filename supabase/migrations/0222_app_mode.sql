-- ============================================================================
-- Migration 0222: the app's mode, normal, read only or closed
--
-- ADDITIVE ONLY. One new table with one row; no other row is written,
-- changed or removed.
--
-- Item 1 of the owner's report, decided on 2026-11-19 (script 292): the
-- owners stop the app from their page in an emergency. 'read_only': the
-- players browse the results and the boards; saving or deleting a
-- prediction, the chat, the groups, the name and the picture are refused;
-- signing in, the devices, support and deleting an account stay open.
-- 'closed': only signing in and deleting an account. The admins pass in
-- both, to test. The scheduled jobs go on: each has its own switch.
--
-- The server reads it before every request, kept ten seconds at most. No
-- client role reads it.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists ops.app_mode (
  id         boolean     primary key default true,
  mode       text        not null default 'normal',
  reason     text,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  constraint app_mode_single_row check (id),
  constraint app_mode_mode_check
    check (mode in ('normal', 'read_only', 'closed')),
  constraint app_mode_reason_not_blank
    check (reason is null or length(btrim(reason)) > 0),
  constraint app_mode_changed_by_fkey
    foreign key (changed_by) references identity.users (id)
    on delete set null
);

comment on table ops.app_mode is
  'The app''s mode (script 292): normal, read_only or closed, in the '
  'owners'' hands. One row; the server reads it before every request.';

insert into ops.app_mode (id, mode) values (true, 'normal')
on conflict (id) do nothing;

alter table ops.app_mode enable row level security;
revoke all on ops.app_mode from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0222_app_mode')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select mode, reason, changed_at from ops.app_mode;     -- normal
