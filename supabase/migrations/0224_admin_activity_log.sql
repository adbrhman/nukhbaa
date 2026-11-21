-- ============================================================================
-- Migration 0224: the admins' activity log, for the owners
--
-- ADDITIVE ONLY. One new table, append-only; no other row is written,
-- changed or removed.
--
-- Script 300 (owner decision 2026-11-21): the owners see every change an
-- admin made, with his name, to check it. Nothing an admin does is refused
-- by this: the server keeps one row per write an admin made (a POST, PUT,
-- PATCH or DELETE answered below 400) on the admin paths (/admin, /fixtures,
-- /competitions, /seasons but a player's own prediction, ...): who, the
-- method, the path (which names the target) and the answer. Read by
-- GET /owner/admin-activity alone, behind the owner gate; no client role
-- reads it.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists admin.admin_activity_log (
  id          bigint      generated always as identity primary key,
  actor_id    uuid        not null,
  method      text        not null,
  path        text        not null,
  status      integer     not null,
  occurred_at timestamptz not null default now(),
  constraint admin_activity_log_actor_id_fkey
    foreign key (actor_id) references identity.users (id) on delete restrict,
  constraint admin_activity_log_method_check
    check (method in ('POST', 'PUT', 'PATCH', 'DELETE')),
  constraint admin_activity_log_path_check
    check (path like '/%' and char_length(path) <= 300),
  constraint admin_activity_log_status_check
    check (status between 100 and 399)
);

comment on table admin.admin_activity_log is
  'Every change an admin made, for the owners (script 300): one row per '
  'admin write answered below 400. Append-only.';

create index if not exists admin_activity_log_occurred_idx
  on admin.admin_activity_log (occurred_at desc, id desc);

create or replace function admin.reject_admin_activity_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'admin.admin_activity_log is append-only: % is forbidden', tg_op
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists admin_activity_log_reject_mutation
  on admin.admin_activity_log;
create trigger admin_activity_log_reject_mutation
  before update or delete on admin.admin_activity_log
  for each row execute function admin.reject_admin_activity_mutation();

alter table admin.admin_activity_log enable row level security;
revoke all on admin.admin_activity_log from anon, authenticated;
revoke all on function admin.reject_admin_activity_mutation()
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0224_admin_activity_log')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0224_admin_activity_log';             -- one row
-- select count(*) from admin.admin_activity_log;          -- 0 before use
