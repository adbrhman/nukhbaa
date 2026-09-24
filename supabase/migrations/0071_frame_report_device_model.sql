-- ============================================================================
-- Migration 0071: the device model on a frame report (2026-09-24)
--
-- ops.frame_reports gains device_model: the maker and model the OS reports
-- (`samsung SM-A105F`), read through device_info_plus -- already a direct
-- dependency of the in-app updater. Nullable: apps from before this
-- migration send none, and the web has no model.
--
-- The admin dashboard lists models only once at least three distinct
-- players report them (GET /admin/frame-stats), so no row there describes
-- one person's phone. The column itself stays server-only like the table.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

alter table ops.frame_reports
  add column if not exists device_model text;

alter table ops.frame_reports
  drop constraint if exists frame_reports_device_model_check;

alter table ops.frame_reports
  add constraint frame_reports_device_model_check
  check (device_model is null or device_model ~ '^[0-9A-Za-z ._()+-]{1,60}$');

comment on column ops.frame_reports.device_model is
  'Maker and model the OS reports; null for the web and for apps older '
  'than 0071. Listed to the admin only per model with 3+ distinct users.';

commit;
