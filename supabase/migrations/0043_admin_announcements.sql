-- ============================================================================
-- Migration 0043 -- Admin announcements: the free-text instruction an admin
-- broadcasts to every active user, delivered through the existing Tier-3
-- Notifications surface.
--
-- Why a SEPARATE table rather than a `body` column on
-- notification.notifications: that table is documented (migration 0009) as
-- carrying NO free text (decision #1 / ADR-001), and a broadcast writes ONE
-- row per recipient -- storing the same paragraph N times would be both a
-- duplication and a breach of that invariant. The text is therefore its own
-- small aggregate written ONCE, and each recipient's notification merely
-- REFERENCES it (announcement_id), exactly as fixture_scored references a
-- fixture. Editing is out of scope: an announcement is append-only, like the
-- audit trail.
--
-- Additive and forward-only. No existing row is touched: announcement_id is
-- NULL on every pre-existing notification, and the existing enum values are
-- untouched.
--
-- ALTER TYPE ... ADD VALUE is safe here: the new value is not referenced by
-- any DML in this same file, only by application code that runs afterward.
-- ============================================================================

alter type notification.notification_kind
  add value if not exists 'admin_announcement';

create table if not exists notification.announcements (
  id         uuid primary key,
  title      text not null,
  body       text not null,
  author_id  uuid not null,
  created_at timestamptz not null default now(),
  constraint announcements_author_id_fkey
    foreign key (author_id) references identity.users (id) on delete cascade,
  constraint announcements_title_not_blank check (length(btrim(title)) > 0),
  constraint announcements_body_not_blank check (length(btrim(body)) > 0),
  constraint announcements_title_len check (length(title) <= 120),
  constraint announcements_body_len check (length(body) <= 1000)
);

comment on table notification.announcements is
  'One admin broadcast (Tier-3, rebuildable): the free text of an '
  'administrative instruction, written ONCE and referenced by the per-'
  'recipient notification.notifications rows (announcement_id). Append-only '
  'in practice -- there is no edit path. Backend owns writes; the client '
  'never reads this table directly (it arrives joined onto GET '
  '/notifications).';

create index if not exists announcements_created_at_idx
  on notification.announcements (created_at desc);

alter table notification.notifications
  add column if not exists announcement_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'notifications_announcement_id_fkey'
  ) then
    alter table notification.notifications
      add constraint notifications_announcement_id_fkey
      foreign key (announcement_id)
      references notification.announcements (id)
      on delete cascade;
  end if;
end
$$;

comment on column notification.notifications.announcement_id is
  'Referenced admin announcement (admin_announcement). The link is FROM '
  'notification TO the announcement text -- no recipient reference is ever '
  'added to an announcement row. NULL for every other kind.';

-- ---------------------------------------------------------------------------
-- Row-Level Security -- backend-only surface, deny everything to the client.
-- The announcement text reaches a user ONLY through their own notification
-- row on GET /notifications (bearer auth, recipient-scoped), never by reading
-- this table: a direct client read would expose every broadcast regardless of
-- recipient. The service role bypasses RLS, so these policies constrain only
-- the anon/authenticated surface (Axiom 6 -- the DB is the backstop).
-- ---------------------------------------------------------------------------
alter table notification.announcements enable row level security;

revoke select, insert, update, delete, truncate on notification.announcements
  from anon, authenticated;

drop policy if exists announcements_no_client_read on notification.announcements;
create policy announcements_no_client_read
  on notification.announcements
  for select
  to anon, authenticated
  using (false);
