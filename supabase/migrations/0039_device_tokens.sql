-- Migration 0039 — Device tokens: FCM push-notification delivery targets.
--
-- One row per registered device (Android only, at least initially): a
-- Firebase Cloud Messaging registration token bound to the user signed in on
-- that device. Tier-3 (Deployment ADR 0007 §2.4): rebuildable, never a
-- source of truth — losing this table only means a device stops receiving
-- pushes until it re-registers; it never blocks or corrupts Prediction/
-- Scoring/Ledger/Leaderboard.
--
-- token is the primary key, not a surrogate uuid: FCM tokens are themselves
-- globally unique and rotate over a device's lifetime (reinstall, app-data
-- clear, token refresh). Registering the SAME token again — from the same
-- user, or after a different user signs in on the same device — is an
-- upsert: ON CONFLICT (token) DO UPDATE, so a re-registered token always
-- reflects whichever user last authenticated on that device (never
-- accumulates stale duplicate rows).
--
-- platform is a closed check constraint, not yet a schema-level enum,
-- mirroring the light touch of a Tier-3 support table: 'android' today; the
-- column exists now so an iOS token would fit without a new migration later.
--
-- No domain-level validity beyond non-empty (the shape of an FCM token is an
-- opaque string owned by Firebase, not this platform's business rule) — this
-- table is closer to a session/credential record than a modelled aggregate,
-- which is why it lives directly as a thin infrastructure-facing surface
-- inside the existing `notification` schema rather than a new one.
create table if not exists notification.device_tokens (
  token      text primary key,
  user_id    uuid not null,
  platform   text not null,
  updated_at timestamptz not null default now(),
  constraint device_tokens_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete cascade,
  constraint device_tokens_platform_check
    check (platform in ('android', 'ios'))
);

comment on table notification.device_tokens is
  'One row per registered FCM device token (Tier-3, rebuildable). token is '
  'the primary key; re-registering an existing token upserts user_id/'
  'platform/updated_at so a device always reflects whoever last '
  'authenticated on it. Backend-only surface: no client RLS read/write '
  'policy is granted.';

-- The reminder job (Phase 5) scans "every token belonging to a user", so the
-- hot lookup is by user_id, not by token (already the primary key).
create index if not exists device_tokens_user_id_idx
  on notification.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Row-Level Security — backend-only surface, deny everything to the client.
--
-- Unlike notifications (a client-readable recipient-scoped surface), a
-- device token is never read or written directly by the client through
-- Supabase: the app registers it by calling the backend route
-- (POST /me/device-token, bearer auth), and the backend (service role) reads
-- every token when it sends a push — the service role bypasses RLS
-- entirely, so these policies constrain only the anon/authenticated client
-- surface, which gets nothing (Axiom 6 — the DB is the backstop, not the
-- first line of defence).
-- ---------------------------------------------------------------------------
alter table notification.device_tokens enable row level security;

revoke select, insert, update, delete, truncate on notification.device_tokens
  from anon, authenticated;

drop policy if exists device_tokens_no_client_read on notification.device_tokens;
create policy device_tokens_no_client_read
  on notification.device_tokens
  for select
  to anon, authenticated
  using (false);
