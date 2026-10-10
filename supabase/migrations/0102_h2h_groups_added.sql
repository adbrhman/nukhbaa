-- ============================================================================
-- Migration 0102: the admin log knows "groups added"
--
-- ADDITIVE ONLY. 0101's admin log accepts a closed list of actions; an admin
-- may now add groups to a head-to-head month already drawn (decided
-- 2026-10-11, when the October pilot grew from one group to four), and that
-- action is logged as 'groups_added'. The check is replaced by the same list
-- plus that one word. No table, row or point is changed; the groups
-- themselves are ordinary rows of 0100's h2h_leagues and h2h_league_members.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

alter table gamification.h2h_admin_actions
  drop constraint if exists h2h_admin_actions_action_known;

alter table gamification.h2h_admin_actions
  add constraint h2h_admin_actions_action_known check (action in (
    'settings_saved', 'day_excluded', 'day_included', 'round_approved',
    'round_withdrawn', 'seat_added', 'jobs_run', 'pilot_started',
    'groups_added'
  ));

insert into ops.applied_migrations (version)
values ('0102_h2h_groups_added')
on conflict (version) do nothing;

commit;
