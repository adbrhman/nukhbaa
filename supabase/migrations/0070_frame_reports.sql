-- ============================================================================
-- Migration 0070: frame smoothness from every device (2026-09-24)
--
-- One table -- ops.frame_reports, one row per app session the app reports
-- (POST /me/frame-report): how many frames it drew, how many ran past one
-- refresh interval of the display (slow) or past 700 ms (frozen), and the
-- slowest. Read by GET /admin/frame-stats for the admin dashboard.
--
-- No screen names, no content, no device identifiers: counts, the build's
-- commit, the platform and the display's refresh rate. Rows go with their
-- user (on delete cascade).
--
-- Server-only: RLS on, no policy, nothing granted to anon or authenticated,
-- as 0069 did for notification.push_opens.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists ops;

comment on schema ops is
  'Operations-owned: how the app runs on devices, not what players do. '
  'Server-only.';

revoke all on schema ops from anon, authenticated;

create table if not exists ops.frame_reports (
  id              bigint generated always as identity primary key,
  user_id         uuid        not null
    references identity.users (id) on delete cascade,
  reported_at     timestamptz not null default now(),
  build           text        not null,
  platform        text        not null,
  refresh_rate_hz integer     not null,
  frames          integer     not null,
  slow_frames     integer     not null,
  frozen_frames   integer     not null,
  worst_frame_ms  integer     not null,
  constraint frame_reports_platform_check
    check (platform in ('android', 'ios', 'web')),
  constraint frame_reports_build_check
    check (build ~ '^[0-9A-Za-z._-]{1,40}$'),
  constraint frame_reports_refresh_check
    check (refresh_rate_hz between 1 and 480),
  constraint frame_reports_counts_check
    check (
      frames between 1 and 10000000
      and slow_frames between 0 and frames
      and frozen_frames between 0 and slow_frames
    ),
  constraint frame_reports_worst_check
    check (worst_frame_ms between 0 and 600000)
);

comment on table ops.frame_reports is
  'One row per app session: frames drawn, slow (past one refresh interval), '
  'frozen (past 700 ms), slowest. Written by POST /me/frame-report only; '
  'read by GET /admin/frame-stats.';

create index if not exists frame_reports_reported_idx
  on ops.frame_reports (reported_at);

alter table ops.frame_reports enable row level security;
revoke all on ops.frame_reports from anon, authenticated;

commit;
