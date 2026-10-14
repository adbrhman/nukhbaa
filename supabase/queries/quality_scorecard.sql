-- The quality scorecard's read of the players' data (script 72).
--
-- Read-only: .github/workflows/quality-scorecard.yml runs it inside a
-- read-only transaction and prints the one JSON row to a file
-- on the runner; tooling/quality/scorecard.mjs turns it into rates and
-- verdicts. Counts never reach the public run summary, only percentages.
--
-- Last 7 days:
--   platforms   -- per platform: sessions reported (POST /me/frame-report,
--                  0070), sessions with a frozen frame (> 700 ms), frames
--                  drawn and frames slower than one refresh interval;
--   open_errors -- per severity and source: error groups (0087) still new
--                  or in progress, critical or high, seen in the window.
-- Tested by supabase/tests/quality_scorecard_query_test.sql.
select json_build_object(
  'window_days', 7,
  'platforms', coalesce((
    select json_agg(p order by p.platform)
    from (
      select r.platform,
             count(*) as sessions,
             count(*) filter (where r.frozen_frames > 0) as frozen_sessions,
             sum(r.frames)::bigint as frames,
             sum(r.slow_frames)::bigint as slow_frames
      from ops.frame_reports r
      where r.reported_at >= now() - interval '7 days'
      group by r.platform
    ) p
  ), '[]'::json),
  'open_errors', coalesce((
    select json_agg(e order by e.severity, e.source)
    from (
      select g.severity, g.source, count(*) as groups
      from ops.error_groups g
      where g.status in ('new', 'in_progress')
        and g.severity in ('critical', 'high')
        and g.last_seen_at >= now() - interval '7 days'
      group by g.severity, g.source
    ) e
  ), '[]'::json)
) as scorecard;
