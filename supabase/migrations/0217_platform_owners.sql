-- ============================================================================
-- Migration 0217: the owner seats, by account id
--
-- ADDITIVE ONLY. One new table and one view; no row of any other table is
-- written, changed or removed.
--
-- Decided by the owner on 2026-11-19 (decision Q01, script 285): the owner
-- is known by his account id, never by an e-mail written in the code. One
-- primary seat and backup seats. The server reads the owners from here for
-- every owner-only tool, for the crowning it does as the owner, and for the
-- alerts only the owners receive.
--
-- 1. admin.platform_owners: one row per seat. At most one primary. An
--    account keeps its row when it changes; a seat is never deleted with an
--    account (accounts are never deleted: 0178 erases, it does not delete).
-- 2. admin.active_owners: the seats whose account is an active admin that
--    was not erased. A seat whose account cannot act is no owner.
--
-- No client role reads either: the server alone does. The seats are filled
-- by the owner in the SQL Editor, by account e-mail typed there, so no
-- e-mail is kept in the repository.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists admin.platform_owners (
  user_id  uuid        primary key,
  seat     text        not null,
  added_at timestamptz not null default now(),
  constraint platform_owners_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete restrict,
  constraint platform_owners_seat_check
    check (seat in ('primary', 'backup'))
);

comment on table admin.platform_owners is
  'The owner seats (script 285, decision Q01): one primary and backups, by '
  'account id. The server reads them through admin.active_owners.';

-- At most one primary seat.
create unique index if not exists platform_owners_one_primary
  on admin.platform_owners ((seat))
  where seat = 'primary';

create or replace view admin.active_owners as
  select o.user_id, o.seat, o.added_at
  from admin.platform_owners o
  join identity.users u
    on u.id = o.user_id
  where u.role = 'admin'
    and u.status = 'active'
    and u.deleted_at is null;

comment on view admin.active_owners is
  'The owner seats whose account is an active, not erased admin (script '
  '285). The server orders them primary first.';

alter table admin.platform_owners enable row level security;
revoke all on admin.platform_owners from anon, authenticated;
revoke all on admin.active_owners from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0217_platform_owners')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0217_platform_owners';            -- one row
-- select seat, user_id from admin.active_owners
--  order by (seat = 'primary') desc, added_at;         -- your two seats
