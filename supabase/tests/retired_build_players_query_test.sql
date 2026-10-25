-- End-to-end test of PostgresRetiredBuildReader.playersSql (script 149):
-- the players whose newest Android session ran a build first seen before
-- the cutoff, the head-to-head tab (2026-10-10 00:00 Riyadh). The PREPARE
-- statement is the adapter's constant, text for text, with @name::type
-- turned into $n::type. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- playersSql
PREPARE retired_players(timestamptz) AS

WITH first_seen AS (
  SELECT build, min(reported_at) AS first_seen
  FROM ops.frame_reports
  WHERE platform = 'android'
  GROUP BY build
),
latest AS (
  SELECT DISTINCT ON (user_id) user_id, build
  FROM ops.frame_reports
  WHERE platform = 'android'
  ORDER BY user_id, reported_at DESC
)
SELECT l.user_id::text AS user_id
FROM latest l
JOIN first_seen f ON f.build = l.build
WHERE f.first_seen < $1::timestamptz;

-- Five players. Build 'old1111' first reported on 30 September, 'new2222'
-- on 12 October (by p3), 'web3333' only from the web, early.
-- p1: only the old build.            -> retired
-- p2: the old build, then the new.   -> not retired (newest is new)
-- p3: the new build, then the old.   -> retired (newest is old)
-- p4: only the new build.            -> not retired
-- p5: the web build, before cutoff.  -> not retired (not Android)
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0149-4000-8149-00000000000' || n)::uuid, 'r' || n || '@t.io', now()
  from generate_series(1, 5) n;
insert into identity.users (id, email, display_name)
select ('00000000-0149-4000-8149-00000000000' || n)::uuid, 'r' || n || '@t.io', 'R ' || n
  from generate_series(1, 5) n;

insert into ops.frame_reports
  (user_id, reported_at, build, platform, refresh_rate_hz, frames,
   slow_frames, frozen_frames, worst_frame_ms) values
  ('00000000-0149-4000-8149-000000000001', '2026-09-30 10:00Z', 'old1111', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000001', '2026-10-20 10:00Z', 'old1111', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000002', '2026-10-01 10:00Z', 'old1111', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000002', '2026-10-21 10:00Z', 'new2222', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000003', '2026-10-12 10:00Z', 'new2222', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000003', '2026-10-22 10:00Z', 'old1111', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000004', '2026-10-15 10:00Z', 'new2222', 'android', 60, 100, 1, 0, 20),
  ('00000000-0149-4000-8149-000000000005', '2026-09-28 10:00Z', 'web3333', 'web', 60, 100, 1, 0, 20);

create temp table out as execute retired_players('2026-10-09 21:00Z');
create temp table early as execute retired_players('2026-09-01 00:00Z');
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id order by user_id) from out)
      = array['00000000-0149-4000-8149-000000000001',
              '00000000-0149-4000-8149-000000000003'],
    'the players whose newest Android session ran a build from before the tab');
  perform pg_temp.check((select count(*) from early) = 0,
    'a cutoff before every build retires nobody');
end $$;

rollback;
