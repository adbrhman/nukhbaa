-- supabase/queries/quality_scorecard.sql (script 72): the scorecard's
-- read of the players' data -- per-platform frame counts and the serious
-- errors still open -- over the last 7 days only. Rolled back at the end.
\set ON_ERROR_STOP on
\set scorecard_query `cat supabase/queries/quality_scorecard.sql`
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8172-0000000000a1', 'a172@t.io', now()),
  ('00000000-0000-4000-8172-0000000000a2', 'b172@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0000-4000-8172-0000000000a1', 'a172@t.io', 'A172'),
  ('00000000-0000-4000-8172-0000000000a2', 'b172@t.io', 'B172');

-- Three Android sessions (one with a frozen frame), one web session, and
-- one Android session eight days old that the window leaves out.
insert into ops.frame_reports
  (user_id, reported_at, build, platform, refresh_rate_hz, frames, slow_frames, frozen_frames, worst_frame_ms)
values
  ('00000000-0000-4000-8172-0000000000a1', now() - interval '1 hour', 'b172', 'android', 60, 1000, 50, 0, 40),
  ('00000000-0000-4000-8172-0000000000a1', now() - interval '2 days', 'b172', 'android', 60, 2000, 100, 2, 900),
  ('00000000-0000-4000-8172-0000000000a2', now() - interval '6 days', 'b172', 'android', 90, 1000, 0, 0, 10),
  ('00000000-0000-4000-8172-0000000000a2', now() - interval '3 hours', 'b172', 'web', 60, 500, 25, 0, 60),
  ('00000000-0000-4000-8172-0000000000a2', now() - interval '8 days', 'b172', 'android', 60, 9000, 9000, 900, 5000);

-- Counted: a new critical server error and an in-progress high Android
-- error, both seen this week. Left out: a fixed high error, a high error
-- last seen ten days ago, and a medium one.
insert into ops.error_groups
  (fingerprint, problem_code, source, error_type, message, severity, status,
   first_build, last_build, first_seen_at, last_seen_at)
values
  ('0172000000000001', 'AAAA', 'server', 'StateError', 'm1', 'critical', 'new', 'b172', 'b172', now() - interval '1 day', now() - interval '1 hour'),
  ('0172000000000002', 'AAAB', 'android', 'TypeError', 'm2', 'high', 'in_progress', 'b172', 'b172', now() - interval '3 days', now() - interval '2 days'),
  ('0172000000000003', 'AAAC', 'android', 'TypeError', 'm3', 'high', 'fixed', 'b172', 'b172', now() - interval '3 days', now() - interval '1 day'),
  ('0172000000000004', 'AAAD', 'web', 'TypeError', 'm4', 'high', 'new', 'b172', 'b172', now() - interval '20 days', now() - interval '10 days'),
  ('0172000000000005', 'AAAE', 'web', 'TypeError', 'm5', 'medium', 'new', 'b172', 'b172', now() - interval '1 day', now() - interval '1 hour');

create temp table card as :scorecard_query

do $$
declare
  c json := (select scorecard from card);
  android json := c->'platforms'->0;
  web json := c->'platforms'->1;
begin
  if (c->>'window_days')::int is distinct from 7 then
    raise exception 'FAILED: window_days is %, expected 7', c->>'window_days';
  end if;
  if json_array_length(c->'platforms') is distinct from 2 then
    raise exception 'FAILED: % platforms, expected android and web', json_array_length(c->'platforms');
  end if;
  if android->>'platform' is distinct from 'android'
     or (android->>'sessions')::int is distinct from 3
     or (android->>'frozen_sessions')::int is distinct from 1
     or (android->>'frames')::bigint is distinct from 4000
     or (android->>'slow_frames')::bigint is distinct from 150 then
    raise exception 'FAILED: android row %', android;
  end if;
  raise notice 'ok - android: 3 sessions this week, 1 with a frozen frame, 150 of 4000 frames slow (the 8-day-old session is out)';
  if web->>'platform' is distinct from 'web'
     or (web->>'sessions')::int is distinct from 1
     or (web->>'frozen_sessions')::int is distinct from 0
     or (web->>'frames')::bigint is distinct from 500
     or (web->>'slow_frames')::bigint is distinct from 25 then
    raise exception 'FAILED: web row %', web;
  end if;
  raise notice 'ok - web: 1 session, no frozen frame, 25 of 500 frames slow';
  if json_array_length(c->'open_errors') is distinct from 2
     or c->'open_errors'->0->>'severity' is distinct from 'critical'
     or c->'open_errors'->0->>'source' is distinct from 'server'
     or (c->'open_errors'->0->>'groups')::int is distinct from 1
     or c->'open_errors'->1->>'severity' is distinct from 'high'
     or c->'open_errors'->1->>'source' is distinct from 'android'
     or (c->'open_errors'->1->>'groups')::int is distinct from 1 then
    raise exception 'FAILED: open_errors %', c->'open_errors';
  end if;
  raise notice 'ok - open serious errors: 1 critical (server), 1 high (android); fixed, old and medium ones are out';
end $$;

rollback;
