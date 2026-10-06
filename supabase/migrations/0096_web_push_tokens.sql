-- ============================================================================
-- Migration 0096: push tokens from the web build (2026-10-06)
--
-- Phase 3 of the world-class plan, "reach everyone": the iPhone players use
-- the web build, which can now receive pushes once added to the home
-- screen. A browser registers its Firebase Cloud Messaging token like a
-- phone, as platform 'web'.
--
-- notification.device_tokens' closed platform check (0039) gains 'web'.
-- RegisterDeviceToken checks first; this is the backstop. Every existing
-- row stays valid: the set only grows.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

alter table notification.device_tokens
  drop constraint if exists device_tokens_platform_check;
alter table notification.device_tokens
  add constraint device_tokens_platform_check
  check (platform in ('android', 'ios', 'web'));

insert into ops.applied_migrations (version)
values ('0096_web_push_tokens')
on conflict (version) do nothing;

commit;
