-- ============================================================================
-- Migration 0223: the owners' hand on the admins, and its log
--
-- ADDITIVE ONLY. One new append-only table and one function; no other row
-- is written, changed or removed.
--
-- Item 4 of the owner's report and decision Q01 (script 294): the owners
-- make a player an admin, take the role back, or end an account's
-- sessions, from their page, always for a reason, no longer from the SQL
-- editor. An owner seat's admin role is never taken back here, so the
-- last owner can never be disabled.
--
-- 1. admin.role_changes: who, what (promote | revoke | end_sessions), why,
--    by whom, when. Append-only; read by the owners' page alone.
-- 2. admin.end_user_sessions(uuid): signs the account out of every phone
--    (its refresh tokens and sessions, as identity.delete_account does).
--    A token already given works until it expires (an hour at most), but
--    the server reads the role and the status on every request, so a
--    revoked admin is a player from his next request.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists admin.role_changes (
  id             bigint      generated always as identity primary key,
  user_id        uuid        not null,
  action         text        not null,
  reason         text        not null,
  changed_by     uuid,
  sessions_ended integer,
  occurred_at    timestamptz not null default now(),
  constraint role_changes_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete cascade,
  constraint role_changes_changed_by_fkey
    foreign key (changed_by) references identity.users (id)
    on delete set null,
  constraint role_changes_action_check
    check (action in ('promote', 'revoke', 'end_sessions')),
  constraint role_changes_reason_check
    check (length(btrim(reason)) between 1 and 200),
  constraint role_changes_sessions_check
    check (sessions_ended is null or sessions_ended >= 0)
);

comment on table admin.role_changes is
  'The owners'' hand on the admins (script 294): promote, revoke, '
  'end_sessions, each with its reason. Append-only.';

create index if not exists role_changes_occurred_idx
  on admin.role_changes (occurred_at desc, id desc);

create or replace function admin.reject_role_change_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'admin.role_changes is append-only: % is forbidden', tg_op
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists role_changes_reject_mutation on admin.role_changes;
create trigger role_changes_reject_mutation
  before update on admin.role_changes
  for each row execute function admin.reject_role_change_mutation();

alter table admin.role_changes enable row level security;
revoke all on admin.role_changes from anon, authenticated;
revoke all on function admin.reject_role_change_mutation()
  from public, anon, authenticated;

create or replace function admin.end_user_sessions(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sessions integer;
begin
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics v_sessions = row_count;
  return v_sessions;
end;
$$;

revoke all on function admin.end_user_sessions(uuid)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0223_admin_role_changes')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0223_admin_role_changes';            -- one row
-- select count(*) from admin.role_changes;               -- 0 before use
