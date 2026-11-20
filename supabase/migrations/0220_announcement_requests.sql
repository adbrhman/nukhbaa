-- ============================================================================
-- Migration 0220: the admins' announcements held for an owner seat
--
-- ADDITIVE ONLY. One new table; no other row is written, changed or
-- removed.
--
-- Decided by the owner on 2026-11-20, amending Q07 (script 290): an owner
-- seat's announcement is published at once; any other admin's is held here
-- until an owner seat publishes it to every active player or rejects it.
-- The admin reads that it will be published after its content is
-- reviewed, and, if rejected, only that it was not approved.
--
-- The id is the admin's own request id, and the announcement's id once
-- published (notification.announcements, migration 0043): the same "send"
-- pressed again is the same request. Only the server reads or writes it.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists notification.announcement_requests (
  id          uuid        primary key,
  author_id   uuid        not null,
  title       text        not null,
  body        text        not null,
  status      text        not null default 'pending',
  created_at  timestamptz not null default now(),
  decided_by  uuid,
  decided_at  timestamptz,
  recipients  integer,
  constraint announcement_requests_author_id_fkey
    foreign key (author_id) references identity.users (id) on delete cascade,
  constraint announcement_requests_decided_by_fkey
    foreign key (decided_by) references identity.users (id)
    on delete set null,
  constraint announcement_requests_status_check
    check (status in ('pending', 'published', 'rejected')),
  constraint announcement_requests_title_check
    check (length(btrim(title)) between 1 and 120),
  constraint announcement_requests_body_check
    check (length(btrim(body)) between 1 and 1000),
  constraint announcement_requests_decided_check
    check ((status = 'pending') = (decided_at is null)),
  constraint announcement_requests_recipients_check
    check (recipients is null or recipients >= 0)
);

comment on table notification.announcement_requests is
  'An admin''s announcement held for an owner seat (script 290): pending, '
  'then published to every active player or rejected. The id is the '
  'admin''s request id, and the announcement''s id once published.';

create index if not exists announcement_requests_status_idx
  on notification.announcement_requests (status, created_at desc);
create index if not exists announcement_requests_author_idx
  on notification.announcement_requests (author_id, created_at desc);

alter table notification.announcement_requests enable row level security;
revoke all on notification.announcement_requests from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0220_announcement_requests')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0220_announcement_requests';         -- one row
-- select status, count(*) from notification.announcement_requests
--  group by status;                                      -- none at first
