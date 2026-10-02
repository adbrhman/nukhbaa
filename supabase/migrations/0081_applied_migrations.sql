-- ============================================================================
-- Migration 0081: a record of the migrations applied to this database
--
-- ADDITIVE ONLY. One table; no existing row is touched.
--
-- Why: migrations reach production by hand (SQL Editor) while Northflank
-- redeploys the server on every push, so code can go live before the
-- migration it needs. Nothing recorded which files the live database had
-- seen. From now on every migration ends by inserting its own file name
-- here, and .github/workflows/migration-drift.yml compares this table with
-- supabase/migrations after each push and every day, and fails -- with the
-- missing file names -- when the live database is behind. The check only
-- reads; production is never written to by CI.
--
-- The backfill below records every migration up to this one as applied:
-- apply this file only once the live database has all of them (the same
-- assumption every previous hand-applied migration made).
--
-- Safe to re-run.
-- ============================================================================

begin;

create schema if not exists ops;

create table if not exists ops.applied_migrations (
  version    text primary key,
  applied_at timestamptz not null default now(),
  constraint applied_migrations_version_shape
    check (version ~ '^[0-9]{4}_[a-z0-9_]+$')
);

comment on table ops.applied_migrations is
  'One row per migration file (its name without .sql) applied to this '
  'database (0081). Every migration inserts its own row; '
  'migration-drift.yml compares this table with supabase/migrations.';

revoke all on ops.applied_migrations from public;

insert into ops.applied_migrations (version) values
  ('0001_identity'),
  ('0002_competition'),
  ('0003_prediction'),
  ('0004_scoring'),
  ('0005_ledger'),
  ('0006_leaderboard'),
  ('0007_group'),
  ('0008_social'),
  ('0009_notification'),
  ('0010_admin'),
  ('0011_hall_of_fame'),
  ('0012_fixture_schedule'),
  ('0013_football_data'),
  ('0014_prediction_double'),
  ('0015_round_predictions_audit'),
  ('0016_leaderboard_display_name'),
  ('0017_scoring_live_grading'),
  ('0018_hall_of_fame_live_scoring'),
  ('0019_axiom4_fixture_prediction_scoring'),
  ('0020_axiom4_fixture_ledger_social'),
  ('0021_season_calendar_fields'),
  ('0022_seasons_no_overlap'),
  ('0023_fixture_predictions_viewed_audit'),
  ('0024_fixture_schedule_team_ids'),
  ('0025_season_leaderboard_display_name'),
  ('0026_team_logos_storage_bucket'),
  ('0027_fixture_league'),
  ('0028_fixture_point_entries_fixture_score_nonneg'),
  ('0029_reject_fixture_prediction_without_schedule'),
  ('0030_season_rank_snapshots'),
  ('0031_season_standings_accuracy'),
  ('0032_user_avatars'),
  ('0033_avatars_inline'),
  ('0034_snapshot_fixture_standings'),
  ('0036_hide_empty_league_competitions'),
  ('0038_continental_leagues'),
  ('0039_device_tokens'),
  ('0040_reminder_sends'),
  ('0041_notification_fixture_scored'),
  ('0042_user_predictions_viewed_audit'),
  ('0043_admin_announcements'),
  ('0044_fixture_schedule_corrected_audit'),
  ('0045_cup_competitions'),
  ('0046_national_teams'),
  ('0047_server_statement_timeout'),
  ('0048_teams_league_id'),
  ('0049_fixture_schedule_kickoff_index'),
  ('0050_club_world_cup_teams'),
  ('0051_provider_sync_runs'),
  ('0052_uefa_nations_league'),
  ('0053_gamification_events'),
  ('0054_gamification_flags_kpi'),
  ('0055_users_utc_offset'),
  ('0056_ledger_streak_bonus_kind'),
  ('0057_ledger_streak_bonus_guards'),
  ('0058_leaderboard_streak_bonus_points'),
  ('0059_gamification_settled_days'),
  ('0060_gamification_settled_day_seasons'),
  ('0061_weekly_leagues'),
  ('0062_gamification_kpi_views'),
  ('0063_notification_preferences'),
  ('0064_notification_queue'),
  ('0065_user_favorite_teams'),
  ('0066_proactive_pushes'),
  ('0067_weekly_league_rank_marks'),
  ('0068_rank_marks_passed_by'),
  ('0069_gamification_kpis'),
  ('0070_frame_reports'),
  ('0071_frame_report_device_model'),
  ('0072_streak_bonus_weekly_only'),
  ('0073_referrals'),
  ('0074_referral_tie_break'),
  ('0075_referral_idle_and_admin'),
  ('0076_monthly_contest_riyadh_midnight'),
  ('0077_month_champions'),
  ('0078_champion_prize'),
  ('0079_one_double_per_day'),
  ('0080_unscored_results_finder'),
  ('0081_applied_migrations')
on conflict (version) do nothing;

commit;
