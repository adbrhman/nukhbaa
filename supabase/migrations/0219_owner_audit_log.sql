-- ============================================================================
-- Migration 0219: the owners' own audit log
--
-- ADDITIVE ONLY. One new table, append-only; no other row is written,
-- changed or removed.
--
-- Decision Q01 of the owner's report (script 287): what the owners do is
-- kept apart from the admins' log. admin.audit_log, which GET /admin/audit
-- reads, never sees an owner action; this table is read by no admin route
-- and no client role. The server appends one row for every change an owner
-- seat made under /owner (a write answered below 400): who, the method,
-- the path (which names the target) and the answer.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists admin.owner_audit_log (
  id          bigint      generated always as identity primary key,
  actor_id    uuid        not null,
  method      text        not null,
  path        text        not null,
  status      integer     not null,
  occurred_at timestamptz not null default now(),
  constraint owner_audit_log_actor_id_fkey
    foreign key (actor_id) references identity.users (id) on delete restrict,
  constraint owner_audit_log_method_check
    check (method in ('POST', 'PUT', 'PATCH', 'DELETE')),
  constraint owner_audit_log_path_check
    check (path like '/owner/%' and char_length(path) <= 300),
  constraint owner_audit_log_status_check
    check (status between 100 and 399)
);

comment on table admin.owner_audit_log is
  'The owners'' own audit log (script 287, decision Q01): one row per change '
  'an owner seat made under /owner. Append-only; apart from admin.audit_log.';

create index if not exists owner_audit_log_occurred_idx
  on admin.owner_audit_log (occurred_at desc, id desc);

create or replace function admin.reject_owner_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'admin.owner_audit_log is append-only: % is forbidden', tg_op
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists owner_audit_log_reject_mutation
  on admin.owner_audit_log;
create trigger owner_audit_log_reject_mutation
  before update or delete on admin.owner_audit_log
  for each row execute function admin.reject_owner_audit_mutation();

alter table admin.owner_audit_log enable row level security;
revoke all on admin.owner_audit_log from anon, authenticated;
revoke all on function admin.reject_owner_audit_mutation()
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0219_owner_audit_log')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0219_owner_audit_log';               -- one row
-- select count(*) from admin.owner_audit_log;             -- 0 before use
