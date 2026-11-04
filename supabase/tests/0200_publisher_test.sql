-- Migration 0200 (the sports publisher, script 208) and every statement
-- PostgresPublisherStore runs, prepared exactly as the store writes them.
-- Rolled back at the end.
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

create function pg_temp.refused(stmt text, name text, label text)
returns void language plpgsql as $$
declare
  v_name text;
begin
  begin
    execute stmt;
  exception when others then
    get stacked diagnostics v_name = constraint_name;
    perform pg_temp.check(name is null or v_name = name, label || ' (' || coalesce(v_name, sqlerrm) || ')');
    return;
  end;
  raise exception 'FAILED: % (not refused)', label;
end $$;

-- PostgresPublisherStore.settingsSql: 
-- PostgresPublisherStore.settingsSql: 
PREPARE settingsSql AS
SELECT platform, enabled, goals, final_result, hold_seconds,
       min_gap_seconds, daily_cap
FROM publisher.settings;

-- PostgresPublisherStore.saveSettingSql: $1=platform, $2=enabled, $3=goals, $4=final_result, $5=hold, $6=gap, $7=cap, $8=actor
PREPARE saveSettingSql(text, boolean, text, boolean, integer, integer, integer, uuid) AS
INSERT INTO publisher.settings
  (platform, enabled, goals, final_result, hold_seconds, min_gap_seconds,
   daily_cap, updated_at, updated_by)
VALUES ($1::text, $2::boolean, $3::text,
        $4::boolean, $5::integer, $6::integer,
        $7::integer, now(), $8::uuid)
ON CONFLICT (platform) DO UPDATE
SET enabled = EXCLUDED.enabled,
    goals = EXCLUDED.goals,
    final_result = EXCLUDED.final_result,
    hold_seconds = EXCLUDED.hold_seconds,
    min_gap_seconds = EXCLUDED.min_gap_seconds,
    daily_cap = EXCLUDED.daily_cap,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by;

-- PostgresPublisherStore.activeCoverageSql: $1=live_from, $2=now
PREPARE activeCoverageSql(timestamptz, timestamptz) AS
SELECT c.fixture_id::text           AS fixture_id,
       s.home_team                  AS home_team,
       s.away_team                  AS away_team,
       s.home_team_id::text         AS home_team_id,
       s.away_team_id::text         AS away_team_id,
       coalesce(l.name, '')         AS league_name,
       s.kickoff_at                 AS kickoff_at,
       c.known_home                 AS known_home,
       c.known_away                 AS known_away,
       c.known_at                   AS known_at,
       c.added_at                   AS added_at,
       (c.final_queued_at IS NOT NULL) AS final_queued,
       r.home_goals                 AS result_home,
       r.away_goals                 AS result_away
FROM publisher.coverage c
JOIN competition.fixture_schedules s ON s.fixture_id = c.fixture_id
LEFT JOIN football_data.leagues l ON l.id = s.league_id
LEFT JOIN scoring.fixture_results r ON r.fixture_id = c.fixture_id
WHERE c.stopped_at IS NULL
  AND s.hidden_at IS NULL
  AND NOT s.is_test
  AND ((r.fixture_id IS NULL
        AND s.kickoff_at >= $1::timestamptz
        AND s.kickoff_at <= $2::timestamptz + interval '5 minutes')
    OR (r.fixture_id IS NOT NULL
        AND c.final_queued_at IS NULL
        AND s.kickoff_at >= $2::timestamptz - interval '2 days'))
ORDER BY s.kickoff_at, c.fixture_id;

-- PostgresPublisherStore.setKnownSql: $1=home, $2=away, $3=at, $4=fixture_id
PREPARE setKnownSql(integer, integer, timestamptz, uuid) AS
UPDATE publisher.coverage
SET known_home = $1::integer, known_away = $2::integer,
    known_at = $3::timestamptz
WHERE fixture_id = $4::uuid;

-- PostgresPublisherStore.liveGoalsSql: $1=fixture_id
PREPARE liveGoalsSql(uuid) AS
SELECT 
id::text AS id, fixture_id::text AS fixture_id, goal_key, home, before_home,
before_away, state, first_seen_at, feed_minute, moment, scorer, minute_label,
penalty, own_goal, details_tries, card_path
FROM publisher.goals
WHERE fixture_id = $1::uuid AND state <> 'withdrawn'
ORDER BY before_home + before_away, first_seen_at, goal_key;

-- PostgresPublisherStore.confirmedGoalsSql: $1=fixture_id
PREPARE confirmedGoalsSql(uuid) AS
SELECT 
id::text AS id, fixture_id::text AS fixture_id, goal_key, home, before_home,
before_away, state, first_seen_at, feed_minute, moment, scorer, minute_label,
penalty, own_goal, details_tries, card_path
FROM publisher.goals
WHERE fixture_id = $1::uuid AND state = 'confirmed'
ORDER BY before_home + before_away, first_seen_at, goal_key;

-- PostgresPublisherStore.addGoalSql: $1=fixture_id, $2=goal_key, $3=home, $4=before_home, $5=before_away, $6=at, $7=feed_minute
PREPARE addGoalSql(uuid, text, boolean, integer, integer, timestamptz, integer) AS
INSERT INTO publisher.goals
  (fixture_id, goal_key, home, before_home, before_away, first_seen_at,
   feed_minute)
VALUES ($1::uuid, $2::text, $3::boolean,
        $4::integer, $5::integer, $6::timestamptz,
        $7::integer)
ON CONFLICT (fixture_id, goal_key) WHERE state <> 'withdrawn' DO NOTHING;

-- PostgresPublisherStore.withdrawGoalSql: $1=fixture_id, $2=goal_key, $3=at
PREPARE withdrawGoalSql(uuid, text, timestamptz) AS
WITH old AS (
  SELECT id, state
  FROM publisher.goals
  WHERE fixture_id = $1::uuid
    AND goal_key = $2::text
    AND state <> 'withdrawn'
  FOR UPDATE
)
UPDATE publisher.goals g
SET state = 'withdrawn', withdrawn_at = $3::timestamptz
FROM old
WHERE g.id = old.id
RETURNING g.id::text AS id, g.fixture_id::text AS fixture_id, g.goal_key,
          g.home, g.before_home, g.before_away, old.state AS state,
          g.first_seen_at, g.feed_minute, g.moment, g.scorer, g.minute_label,
          g.penalty, g.own_goal, g.details_tries, g.card_path;

-- PostgresPublisherStore.noteDetailsTrySql: $1=goal_id
PREPARE noteDetailsTrySql(uuid) AS
UPDATE publisher.goals SET details_tries = details_tries + 1
WHERE id = $1::uuid;

-- PostgresPublisherStore.confirmGoalSql: $1=at, $2=moment, $3=scorer, $4=minute_label, $5=penalty, $6=own_goal, $7=card_path, $8=goal_id
PREPARE confirmGoalSql(timestamptz, text, text, text, boolean, boolean, text, uuid) AS
UPDATE publisher.goals
SET state = 'confirmed', confirmed_at = $1::timestamptz,
    moment = $2::text, scorer = $3::text,
    minute_label = $4::text, penalty = $5::boolean,
    own_goal = $6::boolean, card_path = $7::text
WHERE id = $8::uuid AND state = 'pending';

-- PostgresPublisherStore.enqueueSql: $1=dedupe_key, $2=fixture_id, $3=goal_id, $4=kind, $5=platform, $6=state, $7=body, $8=card_path, $9=riyadh_day, $10=not_before
PREPARE enqueueSql(text, uuid, uuid, text, text, text, text, text, date, timestamptz) AS
INSERT INTO publisher.posts
  (dedupe_key, fixture_id, goal_id, kind, platform, state, body, card_path,
   riyadh_day, not_before)
VALUES ($1::text, $2::uuid, $3::uuid, $4::text,
        $5::text, $6::text, $7::text, $8::text,
        $9::date, $10::timestamptz)
ON CONFLICT (dedupe_key) DO NOTHING
RETURNING id::text AS id;

-- PostgresPublisherStore.markFinalQueuedSql: $1=at, $2=fixture_id
PREPARE markFinalQueuedSql(timestamptz, uuid) AS
UPDATE publisher.coverage SET final_queued_at = $1::timestamptz
WHERE fixture_id = $2::uuid AND final_queued_at IS NULL;

-- PostgresPublisherStore.interruptedSql: $1=now
PREPARE interruptedSql(timestamptz) AS
UPDATE publisher.posts
SET state = 'uncertain', error = 'interrupted', claimed_until = NULL,
    updated_at = $1::timestamptz
WHERE state = 'queued'
  AND claimed_until IS NOT NULL
  AND claimed_until < $1::timestamptz;

-- PostgresPublisherStore.claimSql: $1=until, $2=now, $3=limit
PREPARE claimSql(timestamptz, timestamptz, integer) AS
UPDATE publisher.posts p
SET claimed_until = $1::timestamptz, updated_at = $2::timestamptz
FROM (
  SELECT id
  FROM publisher.posts
  WHERE state = 'queued'
    AND claimed_until IS NULL
    AND not_before <= $2::timestamptz
    AND (next_attempt_at IS NULL OR next_attempt_at <= $2::timestamptz)
  ORDER BY not_before, created_at
  LIMIT $3::integer
  FOR UPDATE SKIP LOCKED
) due
WHERE p.id = due.id
RETURNING p.id::text AS id, p.fixture_id::text AS fixture_id,
          p.goal_id::text AS goal_id, p.kind, p.platform, p.body,
          p.card_path, p.attempts;

-- PostgresPublisherStore.finishSql: $1=state, $2=external_id, $3=next_attempt_at, $4=error, $5=published_at, $6=inc, $7=at, $8=post_id
PREPARE finishSql(text, text, timestamptz, text, timestamptz, integer, timestamptz, uuid) AS
UPDATE publisher.posts
SET state = $1::text,
    external_id = coalesce($2::text, external_id),
    next_attempt_at = $3::timestamptz,
    error = $4::text,
    published_at = coalesce($5::timestamptz, published_at),
    claimed_until = NULL,
    attempts = attempts + $6::integer,
    updated_at = $7::timestamptz
WHERE id = $8::uuid;

-- PostgresPublisherStore.goalPostsOnSql: $1=platform, $2=riyadh_day
PREPARE goalPostsOnSql(text, date) AS
SELECT count(*)::int AS n,
       max(coalesce(published_at, created_at)) AS last_at
FROM publisher.posts
WHERE platform = $1::text
  AND kind = 'goal'
  AND riyadh_day = $2::date
  AND state IN ('published', 'dry_run', 'ready_to_share', 'shared');

-- PostgresPublisherStore.postedPlatformsSql: $1=goal_id
PREPARE postedPlatformsSql(uuid) AS
SELECT DISTINCT platform
FROM publisher.posts
WHERE goal_id = $1::uuid
  AND kind = 'goal'
  AND state IN ('published', 'shared', 'dry_run');

-- PostgresPublisherStore.goalStandsSql: $1=goal_id
PREPARE goalStandsSql(uuid) AS
SELECT (state = 'confirmed') AS stands
FROM publisher.goals
WHERE id = $1::uuid;

-- PostgresPublisherStore.badgesSql: $1=team_ids
PREPARE badgesSql(text) AS
SELECT b.team_id::text AS team_id, coalesce(t.name, '') AS team_name,
       b.fill, b.label
FROM publisher.club_badges b
LEFT JOIN football_data.teams t ON t.id = b.team_id
WHERE b.team_id = ANY(string_to_array($1::text, ',')::uuid[]);

-- PostgresPublisherStore.allBadgesSql: 
PREPARE allBadgesSql AS
SELECT b.team_id::text AS team_id, coalesce(t.name, '') AS team_name,
       b.fill, b.label
FROM publisher.club_badges b
LEFT JOIN football_data.teams t ON t.id = b.team_id
ORDER BY coalesce(t.name, ''), b.team_id;

-- PostgresPublisherStore.saveBadgeSql: $1=fill, $2=label, $3=actor, $4=team_id
PREPARE saveBadgeSql(text, text, uuid, uuid) AS
INSERT INTO publisher.club_badges (team_id, fill, label, updated_at, updated_by)
SELECT t.id, $1::text, $2::text, now(), $3::uuid
FROM football_data.teams t
WHERE t.id = $4::uuid
ON CONFLICT (team_id) DO UPDATE
SET fill = EXCLUDED.fill, label = EXCLUDED.label, updated_at = now(),
    updated_by = EXCLUDED.updated_by
RETURNING team_id::text AS team_id;

-- PostgresPublisherStore.metricsDueSql: $1=before, $2=limit
PREPARE metricsDueSql(timestamptz, integer) AS
SELECT p.id::text AS id, p.platform, p.external_id
FROM publisher.posts p
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
WHERE p.state = 'published'
  AND p.external_id IS NOT NULL
  AND m.post_id IS NULL
  AND p.published_at < $1::timestamptz
  AND p.published_at > $1::timestamptz - interval '7 days'
ORDER BY p.published_at
LIMIT $2::integer;

-- PostgresPublisherStore.saveMetricsSql: $1=post_id, $2=at, $3=reach, $4=reactions, $5=comments, $6=shares, $7=raw
PREPARE saveMetricsSql(uuid, timestamptz, integer, integer, integer, integer, jsonb) AS
INSERT INTO publisher.post_metrics
  (post_id, read_at, reach, reactions, comments, shares, raw)
VALUES ($1::uuid, $2::timestamptz, $3::integer,
        $4::integer, $5::integer, $6::integer,
        $7::jsonb)
ON CONFLICT (post_id) DO UPDATE
SET read_at = EXCLUDED.read_at, reach = EXCLUDED.reach,
    reactions = EXCLUDED.reactions, comments = EXCLUDED.comments,
    shares = EXCLUDED.shares, raw = EXCLUDED.raw;

-- PostgresPublisherStore.candidatesSql: $1=from, $2=to
PREPARE candidatesSql(timestamptz, timestamptz) AS
SELECT s.fixture_id::text AS fixture_id, s.home_team, s.away_team,
       coalesce(l.name, '') AS league_name, s.kickoff_at,
       (c.fixture_id IS NOT NULL AND c.stopped_at IS NULL) AS covered
FROM competition.fixture_schedules s
LEFT JOIN football_data.leagues l ON l.id = s.league_id
LEFT JOIN publisher.coverage c ON c.fixture_id = s.fixture_id
WHERE s.hidden_at IS NULL
  AND NOT s.is_test
  AND s.kickoff_at >= $1::timestamptz
  AND s.kickoff_at < $2::timestamptz
ORDER BY s.kickoff_at, s.home_team
LIMIT 200;

-- PostgresPublisherStore.coverSql: $1=actor, $2=at, $3=fixture_id
PREPARE coverSql(uuid, timestamptz, uuid) AS
INSERT INTO publisher.coverage (fixture_id, added_by, added_at)
SELECT s.fixture_id, $1::uuid, $2::timestamptz
FROM competition.fixture_schedules s
WHERE s.fixture_id = $3::uuid
  AND s.hidden_at IS NULL
  AND NOT s.is_test
ON CONFLICT (fixture_id) DO UPDATE
SET added_by = CASE WHEN publisher.coverage.stopped_at IS NULL
                    THEN publisher.coverage.added_by
                    ELSE EXCLUDED.added_by END,
    added_at = CASE WHEN publisher.coverage.stopped_at IS NULL
                    THEN publisher.coverage.added_at
                    ELSE EXCLUDED.added_at END,
    known_at = CASE WHEN publisher.coverage.stopped_at IS NULL
                    THEN publisher.coverage.known_at
                    ELSE NULL END,
    stopped_at = NULL
RETURNING fixture_id::text AS fixture_id;

-- PostgresPublisherStore.stopSql: $1=at, $2=fixture_id
PREPARE stopSql(timestamptz, uuid) AS
UPDATE publisher.coverage SET stopped_at = $1::timestamptz
WHERE fixture_id = $2::uuid AND stopped_at IS NULL;

-- PostgresPublisherStore.recentPostsSql: $1=limit
PREPARE recentPostsSql(integer) AS
SELECT 
p.id::text AS id, p.fixture_id::text AS fixture_id,
coalesce(s.home_team || ' - ' || s.away_team, '') AS match_label,
p.kind, p.platform, p.state, p.body, p.card_path, p.external_id, p.error,
p.created_at, p.published_at, p.attempts,
m.reach, m.reactions, m.comments, m.shares
FROM publisher.posts p
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = p.fixture_id
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
ORDER BY p.created_at DESC, p.id
LIMIT $1::integer;

-- PostgresPublisherStore.postSql: $1=post_id
PREPARE postSql(uuid) AS
SELECT 
p.id::text AS id, p.fixture_id::text AS fixture_id,
coalesce(s.home_team || ' - ' || s.away_team, '') AS match_label,
p.kind, p.platform, p.state, p.body, p.card_path, p.external_id, p.error,
p.created_at, p.published_at, p.attempts,
m.reach, m.reactions, m.comments, m.shares
FROM publisher.posts p
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = p.fixture_id
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
WHERE p.id = $1::uuid;

-- PostgresPublisherStore.movePostSql: $1=to, $2=at, $3=post_id, $4=from
PREPARE movePostSql(text, timestamptz, uuid, text) AS
UPDATE publisher.posts
SET state = $1::text,
    updated_at = $2::timestamptz,
    claimed_until = NULL,
    next_attempt_at = NULL,
    not_before = CASE WHEN $1::text = 'queued'
                      THEN least(not_before, $2::timestamptz)
                      ELSE not_before END,
    error = CASE WHEN $1::text = 'queued' THEN NULL ELSE error END
WHERE id = $3::uuid
  AND state = ANY(string_to_array($4::text, ','))
RETURNING id::text AS id;

-- The scenario: one match in play, picked; goals seen, one ruled out; posts
-- queued twice under one key; a claim cut by a restart; a day's count.
insert into football_data.leagues (id, name)
values ('00000000-0000-4000-8000-0000000000a1', 'دوري روشن السعودي');
insert into football_data.teams (id, name) values
  ('00000000-0000-4000-8000-0000000000b1', 'الهلال'),
  ('00000000-0000-4000-8000-0000000000b2', 'النصر');
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id,
   league_id)
values ('00000000-0000-4000-8000-0000000000c1', 'الهلال', 'النصر',
        '2026-11-07 17:00+00', '00000000-0000-4000-8000-0000000000b1',
        '00000000-0000-4000-8000-0000000000b2',
        '00000000-0000-4000-8000-0000000000a1');

-- Defaults until an admin saves; a save is read back.
select pg_temp.check((select count(*) from publisher.settings) = 0,
                     'no setting stored before an admin saves');
execute saveSettingSql('facebook', true, 'all', true, 180, 0, 12,
                       '00000000-0000-4000-8000-0000000000d1');
execute saveSettingSql('facebook', true, 'key', true, 240, 600, 10,
                       '00000000-0000-4000-8000-0000000000d1');
select pg_temp.check(
  (select goals = 'key' and hold_seconds = 240 and daily_cap = 10
     from publisher.settings where platform = 'facebook'),
  'a second save replaces the platform''s setting');
select pg_temp.refused($$execute saveSettingSql('x', true, 'all', true, 30, 0, 12, null)$$,
                       'settings_hold', 'a hold under a minute is refused');

-- Picking a match; a hidden or unknown one is not picked.
execute coverSql('00000000-0000-4000-8000-0000000000d1',
                 '2026-11-07 16:00+00', '00000000-0000-4000-8000-0000000000c1') \gset cov_
select pg_temp.check(:'cov_fixture_id' = '00000000-0000-4000-8000-0000000000c1',
                     'a visible match is picked');
execute coverSql('00000000-0000-4000-8000-0000000000d1',
                 '2026-11-07 16:00+00', '00000000-0000-4000-8000-0000000000c9');
select pg_temp.check((select count(*) from publisher.coverage) = 1,
                     'an unknown match is not picked');

create temp table active as
  execute activeCoverageSql('2026-11-07 15:30+00', '2026-11-07 17:30+00');
select pg_temp.check((select count(*) from active) = 1
                     and (select league_name from active) = 'دوري روشن السعودي'
                     and (select result_home from active) is null,
                     'a picked match in play is active, with its league');
create temp table early as
  execute activeCoverageSql('2026-11-07 13:00+00', '2026-11-07 16:00+00');
select pg_temp.check((select count(*) from early) = 0,
                     'a match an hour away is not active yet');

-- Goals: a second sighting of a live goal keeps the first; a withdrawn key
-- is free again.
execute addGoalSql('00000000-0000-4000-8000-0000000000c1', 'h1', true, 0, 0,
                   '2026-11-07 17:12+00', 9);
execute addGoalSql('00000000-0000-4000-8000-0000000000c1', 'h1', true, 0, 0,
                   '2026-11-07 17:14+00', 10);
select pg_temp.check((select count(*) from publisher.goals) = 1
                     and (select feed_minute from publisher.goals) = 9,
                     'a goal seen twice is kept once, as first seen');
execute withdrawGoalSql('00000000-0000-4000-8000-0000000000c1', 'h1',
                          '2026-11-07 17:16+00') \gset w_
select pg_temp.check(:'w_state' = 'pending'
                     and (select state from publisher.goals) = 'withdrawn',
                     'a withdrawn goal answers the state it was in');
execute addGoalSql('00000000-0000-4000-8000-0000000000c1', 'h1', true, 0, 0,
                   '2026-11-07 17:22+00', 20);
select pg_temp.check((select count(*) from publisher.goals) = 2,
                     'a goal of the same key after a withdrawal is new');
select pg_temp.refused($$insert into publisher.goals (fixture_id, goal_key, home, before_home, before_away, first_seen_at)
                         values ('00000000-0000-4000-8000-0000000000c1', 'h1', true, 0, 0, now())$$,
                       'goals_live_key', 'two live goals never share a key');

-- Confirm it and queue its posts twice: one row per platform.
select id as g_id from publisher.goals where state = 'pending' \gset
execute confirmGoalSql('2026-11-07 17:25+00', 'opener', 'سالم الدوسري', '20',
                       false, false, 'goals/c1/g.jpg', :'g_id');
select pg_temp.check((select state from publisher.goals where id = :'g_id'::uuid) = 'confirmed',
                     'a pending goal is confirmed');
execute enqueueSql('goal:g:facebook', '00000000-0000-4000-8000-0000000000c1',
                     :'g_id', 'goal', 'facebook', 'queued', 'هدف',
                     'goals/c1/g.jpg', '2026-11-07', '2026-11-07 17:25+00');
execute enqueueSql('goal:g:facebook', '00000000-0000-4000-8000-0000000000c1',
                     :'g_id', 'goal', 'facebook', 'queued', 'هدف',
                     'goals/c1/g.jpg', '2026-11-07', '2026-11-07 17:25+00');
select pg_temp.check((select count(*) from publisher.posts) = 1,
                     'a post queued twice under one key is one post');
select id as p_id from publisher.posts \gset

-- Claimed, then the server stops: the next claim marks it uncertain and
-- never hands it out again.
execute claimSql('2026-11-07 17:29+00', '2026-11-07 17:26+00', 4) \gset c1_
select pg_temp.check(:'c1_platform' = 'facebook'
                     and (select claimed_until from publisher.posts) = '2026-11-07 17:29+00',
                     'a due post is claimed');
execute claimSql('2026-11-07 17:30+00', '2026-11-07 17:27+00', 4);
select pg_temp.check((select claimed_until from publisher.posts) = '2026-11-07 17:29+00',
                     'a claimed post is not claimed twice');
execute interruptedSql('2026-11-07 17:40+00');
select pg_temp.check((select state from publisher.posts) = 'uncertain'
                     and (select claimed_until from publisher.posts) is null,
                     'a claim that ran out is uncertain, not sent again');

-- An admin retries it; it is sent and counted in its day.
execute movePostSql('queued', '2026-11-07 17:41+00',
                    :'p_id', 'failed,uncertain') \gset mv_
select pg_temp.check(:'mv_id' = (select id::text from publisher.posts)
                     and (select state from publisher.posts) = 'queued',
                     'an uncertain post goes back to the queue');
execute claimSql('2026-11-07 17:45+00', '2026-11-07 17:42+00', 4) \gset c3_
execute finishSql('published', 'fb_123', null, null, '2026-11-07 17:42+00', 1,
                  '2026-11-07 17:42+00', :'c3_id');
select pg_temp.check((select state = 'published' and attempts = 1 and external_id = 'fb_123'
                        and claimed_until is null from publisher.posts),
                     'a sent post is published, its attempt counted');
create temp table day as
  execute goalPostsOnSql('facebook', '2026-11-07');
select pg_temp.check((select n from day) = 1, 'the day counts its goal post');
create temp table posted as
  execute postedPlatformsSql(:'g_id');
select pg_temp.check((select platform from posted) = 'facebook', 'the goal is known posted on Facebook');
create temp table stands as execute goalStandsSql(:'g_id');
select pg_temp.check((select stands from stands), 'a confirmed goal stands');
execute movePostSql('cancelled', '2026-11-07 17:50+00',
                    :'p_id', 'queued,ready_to_share');
select pg_temp.check((select state from publisher.posts) = 'published',
                     'a published post cannot be cancelled');

-- Metrics once a day has passed.
create temp table due as
  execute metricsDueSql('2026-11-08 18:00+00', 4);
select pg_temp.check((select count(*) from due) = 1, 'a day-old post is due for metrics');
execute saveMetricsSql(:'p_id', '2026-11-08 18:00+00',
                       300, 12, 3, 1, '{"likes": 12}');
create temp table due2 as
  execute metricsDueSql('2026-11-08 18:01+00', 4);
select pg_temp.check((select count(*) from due2) = 0, 'metrics are read once');

-- Badges.
execute saveBadgeSql('#0B4FD8', 'هلال', '00000000-0000-4000-8000-0000000000d1',
                       '00000000-0000-4000-8000-0000000000b1');
execute saveBadgeSql('#0B4FD8', null, '00000000-0000-4000-8000-0000000000d1',
                       '00000000-0000-4000-8000-0000000000b9');
select pg_temp.check((select count(*) from publisher.club_badges) = 1,
                     'a badge is set only for a known club');
create temp table bs as
  execute badgesSql('00000000-0000-4000-8000-0000000000b1,00000000-0000-4000-8000-0000000000b2');
select pg_temp.check((select count(*) from bs) = 1 and (select team_name from bs) = 'الهلال',
                     'badges are read by club id with the club''s name');
select pg_temp.refused($$execute saveBadgeSql('blue', null, null, '00000000-0000-4000-8000-0000000000b1')$$,
                       'club_badges_fill', 'a colour that is not #RRGGBB is refused');

-- The result: the match leaves the live list and waits for its final posts.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
values ('00000000-0000-4000-8000-0000000000c1', 1, 0, '2026-11-07 19:10+00');
create temp table fin as
  execute activeCoverageSql('2026-11-07 16:30+00', '2026-11-07 19:30+00');
select pg_temp.check((select result_home from fin) = 1 and not (select final_queued from fin),
                     'a covered match with a result waits for its final posts');
execute markFinalQueuedSql('2026-11-07 19:31+00', '00000000-0000-4000-8000-0000000000c1');
create temp table fin2 as
  execute activeCoverageSql('2026-11-07 16:31+00', '2026-11-07 19:31+00');
select pg_temp.check((select count(*) from fin2) = 0, 'once queued, the final is not queued again');

-- Stopping keeps everything; picking again reads the match afresh.
execute stopSql('2026-11-07 19:40+00', '00000000-0000-4000-8000-0000000000c1');
select pg_temp.check((select stopped_at is not null from publisher.coverage),
                     'a stop keeps the row');
execute setKnownSql(1, 0, '2026-11-07 19:00+00', '00000000-0000-4000-8000-0000000000c1');
execute coverSql('00000000-0000-4000-8000-0000000000d1',
                   '2026-11-07 19:45+00', '00000000-0000-4000-8000-0000000000c1');
select pg_temp.check((select stopped_at is null and known_at is null
                        and added_at = '2026-11-07 19:45+00'
                      from publisher.coverage),
                     'a match picked again is read afresh');
create temp table cand as
  execute candidatesSql('2026-11-07 00:00+00', '2026-11-08 00:00+00');
select pg_temp.check((select covered from cand), 'the panel lists the match as covered');
create temp table recent as execute recentPostsSql(10);
select pg_temp.check((select match_label from recent) = 'الهلال - النصر'
                     and (select reactions from recent) = 12,
                     'the latest posts carry their match and metrics');
create temp table one as execute postSql(:'p_id');
select pg_temp.check((select count(*) from one) = 1, 'one post is read by id');
create temp table live as
  execute liveGoalsSql('00000000-0000-4000-8000-0000000000c1');
create temp table conf as
  execute confirmedGoalsSql('00000000-0000-4000-8000-0000000000c1');
select pg_temp.check((select count(*) from live) = 1 and (select count(*) from conf) = 1,
                     'live and confirmed goals are read');
execute noteDetailsTrySql(:'g_id');
select pg_temp.check((select details_tries from publisher.goals where id = :'g_id'::uuid) = 1,
                     'a question to the provider is counted');
create temp table st as execute settingsSql;
select pg_temp.check((select count(*) from st) = 1, 'the stored settings are read');
create temp table allb as execute allBadgesSql;
select pg_temp.check((select count(*) from allb) = 1, 'every badge is listed');

-- Nothing of the publisher is open to the app's roles.
select pg_temp.check(not has_table_privilege('anon', 'publisher.posts', 'select')
                     and not has_table_privilege('authenticated', 'publisher.posts', 'select'),
                     'anon and authenticated cannot read the posts');
select pg_temp.check((select public from storage.buckets where id = 'publisher-cards'),
                     'the cards bucket is public');

rollback;
