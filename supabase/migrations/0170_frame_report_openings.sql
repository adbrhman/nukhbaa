-- ============================================================================
-- Migration 0170: when a frozen frame happened (script 73, 2026-10-15)
--
-- The quality scorecard (script 72) found a third of the web sessions with
-- a frame over 700 ms against 2.8% on Android. A frame report said how
-- many froze, not when. ops.frame_reports gains two counts, a subset of
-- frozen_frames each:
--   frozen_at_start  -- in the first 5 seconds after the app opened;
--   frozen_at_resume -- in the first 5 seconds after it came back from the
--                       background (another tab, the home screen).
-- The rest froze while the player was using the app. Nullable, both or
-- neither: apps from before this migration send none. Nothing about
-- screens or content, as before.
--
-- Numbered outside the audit plan's ranges (0110-0149, 0150-0169): the
-- web speed and quality series (scripts 71 on) uses 0170-0179.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

alter table ops.frame_reports
  add column if not exists frozen_at_start integer,
  add column if not exists frozen_at_resume integer;

alter table ops.frame_reports
  drop constraint if exists frame_reports_openings_check;

alter table ops.frame_reports
  add constraint frame_reports_openings_check
  check (
    (frozen_at_start is null) = (frozen_at_resume is null)
    and (
      frozen_at_start is null
      or (
        frozen_at_start >= 0
        and frozen_at_resume >= 0
        and frozen_at_start + frozen_at_resume <= frozen_frames
      )
    )
  );

comment on column ops.frame_reports.frozen_at_start is
  'Frozen frames in the first 5 s after the app opened (0170); null for '
  'apps older than 0170.';
comment on column ops.frame_reports.frozen_at_resume is
  'Frozen frames in the first 5 s after a return from the background '
  '(0170); null for apps older than 0170.';

insert into ops.applied_migrations (version)
values ('0170_frame_report_openings')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0170_frame_report_openings';                    -- 1 row
-- select column_name from information_schema.columns
--  where table_schema = 'ops' and table_name = 'frame_reports'
--    and column_name like 'frozen_at_%';                             -- 2 rows
