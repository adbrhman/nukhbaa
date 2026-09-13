-- ============================================================================
-- Migration 0044 -- admin.audit_action gains 'fixture_schedule_corrected'.
--
-- Editing a fixture's kickoff time is the single most consequential admin
-- action on this platform: the prediction lock is computed from that column,
-- so moving it moves the deadline. Until now RegisterFixtureSchedule and
-- CorrectFixtureSchedule wrote no audit row at all -- the one crown-jewel
-- action with no trace. This token closes that gap; CorrectFixtureSchedule
-- records who changed what, with the old and new kickoff in the reason.
--
-- Additive, forward-only. No existing row is touched.
-- ============================================================================

alter type admin.audit_action
  add value if not exists 'fixture_schedule_corrected';
