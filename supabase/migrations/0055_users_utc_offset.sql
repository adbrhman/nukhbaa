-- ============================================================================
-- Migration 0055: identity.users.utc_offset_minutes (P1-1)
--
-- ADDITIVE ONLY. One nullable column on one existing table, plus its CHECK.
-- No data is written, nothing is dropped, and every existing row stays valid
-- because the column is nullable: NULL means "this user has never reported an
-- offset", which is the state of every row the moment this runs.
--
-- ## What this column is NOT
-- It is NOT the day boundary. Decided 2026-09-19: the daily challenge, the
-- streak and `gamification.daily_active_users` (0054) are all bounded by the
-- RIYADH day -- the same day `sync_provider_fixtures`, `sync_provider_results`
-- and `reminder_sends` (0040) already use. One shared day is what makes
-- "today's fixtures" one set and the standings one table; a per-user day would
-- hand two users different challenges and quietly fork the contest.
--
-- What this column is for is notification TIMING: quiet hours (P3-2) are a
-- statement about the reader's own clock ("not before 09:00 where they are"),
-- and that cannot be answered from a Riyadh day. Nothing reads it yet.
--
-- ## An offset, not a zone
-- A zone name (Asia/Riyadh) carries daylight-saving rules; an integer offset
-- does not. Flutter cannot report an IANA zone without a new dependency, and
-- the no-new-dependencies rule stands, so the client reports
-- `DateTime.now().timeZoneOffset` on every app start instead. Re-reporting is
-- what keeps a traveller -- or a European user in March -- correct: the latest
-- report is always the truest available. For the Gulf audience, which has no
-- daylight saving, offset and zone coincide exactly.
--
-- ## The range
-- -720 (UTC-12:00) .. +840 (UTC+14:00) is the real span of inhabited zones,
-- and every one of them is a whole number of quarter-hours from UTC (Kathmandu
-- +5:45, Chatham +12:45). Anything else is a broken client, not a place. The
-- CHECK mirrors `User.validateUtcOffsetMinutes`, so a rejection in Dart and a
-- rejection in Postgres always agree.
--
-- Forward-only, expand-only. Safe to re-run.
-- ============================================================================

begin;

alter table identity.users
  add column if not exists utc_offset_minutes smallint;

alter table identity.users
  drop constraint if exists users_utc_offset_minutes_range;

alter table identity.users
  add constraint users_utc_offset_minutes_range
  check (
    utc_offset_minutes is null
    or (
      utc_offset_minutes between -720 and 840
      and utc_offset_minutes % 15 = 0
    )
  );

comment on column identity.users.utc_offset_minutes is
  'Minutes the user''s device clock is ahead of UTC, as last reported by the '
  'app on launch (Riyadh = 180). NULL until first reported. Used for '
  'notification timing only -- never for a day boundary: the challenge, the '
  'streak and the KPI views all run on the Riyadh day.';

commit;

-- Verification:
-- select count(*) from identity.users where utc_offset_minutes is not null; -- 0
-- update identity.users set utc_offset_minutes = 7;   -- must fail (not /15)
-- update identity.users set utc_offset_minutes = 900; -- must fail (range)
