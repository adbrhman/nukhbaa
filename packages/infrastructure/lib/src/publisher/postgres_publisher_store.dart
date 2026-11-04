import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [PublisherStore] over the `publisher` schema (migration 0200).
///
/// Reads `competition.fixture_schedules`, `football_data.leagues`,
/// `football_data.teams` and `scoring.fixture_results`; writes only the
/// publisher's own tables. A post is queued under its unique `dedupe_key`
/// (`ON CONFLICT DO NOTHING`), so a goal is never queued twice, and claimed
/// with `FOR UPDATE SKIP LOCKED`.
final class PostgresPublisherStore implements PublisherStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresPublisherStore(this._connection);

  final PostgresConnection _connection;

  /// Every SQL statement, for the SQL test that runs them
  /// (`supabase/tests/0200_publisher_test.sql`).
  static const String settingsSql = '''
SELECT platform, enabled, goals, final_result, hold_seconds,
       min_gap_seconds, daily_cap
FROM publisher.settings
''';

  /// See [settingsSql].
  static const String saveSettingSql = '''
INSERT INTO publisher.settings
  (platform, enabled, goals, final_result, hold_seconds, min_gap_seconds,
   daily_cap, updated_at, updated_by)
VALUES (@platform::text, @enabled::boolean, @goals::text,
        @final_result::boolean, @hold::integer, @gap::integer,
        @cap::integer, now(), @actor::uuid)
ON CONFLICT (platform) DO UPDATE
SET enabled = EXCLUDED.enabled,
    goals = EXCLUDED.goals,
    final_result = EXCLUDED.final_result,
    hold_seconds = EXCLUDED.hold_seconds,
    min_gap_seconds = EXCLUDED.min_gap_seconds,
    daily_cap = EXCLUDED.daily_cap,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by
''';

  /// See [settingsSql].
  static const String activeCoverageSql = '''
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
        AND s.kickoff_at >= @live_from::timestamptz
        AND s.kickoff_at <= @now::timestamptz + interval '5 minutes')
    OR (r.fixture_id IS NOT NULL
        AND c.final_queued_at IS NULL
        AND s.kickoff_at >= @now::timestamptz - interval '2 days'))
ORDER BY s.kickoff_at, c.fixture_id
''';

  /// See [settingsSql].
  static const String setKnownSql = '''
UPDATE publisher.coverage
SET known_home = @home::integer, known_away = @away::integer,
    known_at = @at::timestamptz
WHERE fixture_id = @fixture_id::uuid
''';

  static const String _goalColumns = '''
id::text AS id, fixture_id::text AS fixture_id, goal_key, home, before_home,
before_away, state, first_seen_at, feed_minute, moment, scorer, minute_label,
penalty, own_goal, details_tries, card_path''';

  /// See [settingsSql].
  static const String liveGoalsSql =
      '''
SELECT $_goalColumns
FROM publisher.goals
WHERE fixture_id = @fixture_id::uuid AND state <> 'withdrawn'
ORDER BY before_home + before_away, first_seen_at, goal_key
''';

  /// See [settingsSql].
  static const String confirmedGoalsSql =
      '''
SELECT $_goalColumns
FROM publisher.goals
WHERE fixture_id = @fixture_id::uuid AND state = 'confirmed'
ORDER BY before_home + before_away, first_seen_at, goal_key
''';

  /// See [settingsSql].
  static const String addGoalSql = '''
INSERT INTO publisher.goals
  (fixture_id, goal_key, home, before_home, before_away, first_seen_at,
   feed_minute)
VALUES (@fixture_id::uuid, @goal_key::text, @home::boolean,
        @before_home::integer, @before_away::integer, @at::timestamptz,
        @feed_minute::integer)
ON CONFLICT (fixture_id, goal_key) WHERE state <> 'withdrawn' DO NOTHING
''';

  /// See [settingsSql].
  static const String withdrawGoalSql = '''
WITH old AS (
  SELECT id, state
  FROM publisher.goals
  WHERE fixture_id = @fixture_id::uuid
    AND goal_key = @goal_key::text
    AND state <> 'withdrawn'
  FOR UPDATE
)
UPDATE publisher.goals g
SET state = 'withdrawn', withdrawn_at = @at::timestamptz
FROM old
WHERE g.id = old.id
RETURNING g.id::text AS id, g.fixture_id::text AS fixture_id, g.goal_key,
          g.home, g.before_home, g.before_away, old.state AS state,
          g.first_seen_at, g.feed_minute, g.moment, g.scorer, g.minute_label,
          g.penalty, g.own_goal, g.details_tries, g.card_path
''';

  /// See [settingsSql].
  static const String noteDetailsTrySql = '''
UPDATE publisher.goals SET details_tries = details_tries + 1
WHERE id = @goal_id::uuid
''';

  /// See [settingsSql].
  static const String confirmGoalSql = '''
UPDATE publisher.goals
SET state = 'confirmed', confirmed_at = @at::timestamptz,
    moment = @moment::text, scorer = @scorer::text,
    minute_label = @minute_label::text, penalty = @penalty::boolean,
    own_goal = @own_goal::boolean, card_path = @card_path::text
WHERE id = @goal_id::uuid AND state = 'pending'
''';

  /// See [settingsSql].
  static const String enqueueSql = '''
INSERT INTO publisher.posts
  (dedupe_key, fixture_id, goal_id, kind, platform, state, body, card_path,
   riyadh_day, not_before)
VALUES (@dedupe_key::text, @fixture_id::uuid, @goal_id::uuid, @kind::text,
        @platform::text, @state::text, @body::text, @card_path::text,
        @riyadh_day::date, @not_before::timestamptz)
ON CONFLICT (dedupe_key) DO NOTHING
RETURNING id::text AS id
''';

  /// See [settingsSql].
  static const String markFinalQueuedSql = '''
UPDATE publisher.coverage SET final_queued_at = @at::timestamptz
WHERE fixture_id = @fixture_id::uuid AND final_queued_at IS NULL
''';

  /// See [settingsSql]. A claim that ran out unfinished: the server
  /// stopped while sending, so the post may be out already.
  static const String interruptedSql = '''
UPDATE publisher.posts
SET state = 'uncertain', error = 'interrupted', claimed_until = NULL,
    updated_at = @now::timestamptz
WHERE state = 'queued'
  AND claimed_until IS NOT NULL
  AND claimed_until < @now::timestamptz
''';

  /// See [settingsSql].
  static const String claimSql = '''
UPDATE publisher.posts p
SET claimed_until = @until::timestamptz, updated_at = @now::timestamptz
FROM (
  SELECT id
  FROM publisher.posts
  WHERE state = 'queued'
    AND claimed_until IS NULL
    AND not_before <= @now::timestamptz
    AND (next_attempt_at IS NULL OR next_attempt_at <= @now::timestamptz)
  ORDER BY not_before, created_at
  LIMIT @limit::integer
  FOR UPDATE SKIP LOCKED
) due
WHERE p.id = due.id
RETURNING p.id::text AS id, p.fixture_id::text AS fixture_id,
          p.goal_id::text AS goal_id, p.kind, p.platform, p.body,
          p.card_path, p.attempts
''';

  /// See [settingsSql].
  static const String finishSql = '''
UPDATE publisher.posts
SET state = @state::text,
    external_id = coalesce(@external_id::text, external_id),
    next_attempt_at = @next_attempt_at::timestamptz,
    error = @error::text,
    published_at = coalesce(@published_at::timestamptz, published_at),
    claimed_until = NULL,
    attempts = attempts + @inc::integer,
    updated_at = @at::timestamptz
WHERE id = @post_id::uuid
''';

  /// See [settingsSql].
  static const String goalPostsOnSql = '''
SELECT count(*)::int AS n,
       max(coalesce(published_at, created_at)) AS last_at
FROM publisher.posts
WHERE platform = @platform::text
  AND kind = 'goal'
  AND riyadh_day = @riyadh_day::date
  AND state IN ('published', 'dry_run', 'ready_to_share', 'shared')
''';

  /// See [settingsSql].
  static const String postedPlatformsSql = '''
SELECT DISTINCT platform
FROM publisher.posts
WHERE goal_id = @goal_id::uuid
  AND kind = 'goal'
  AND state IN ('published', 'shared', 'dry_run')
''';

  /// See [settingsSql].
  static const String goalStandsSql = '''
SELECT (state = 'confirmed') AS stands
FROM publisher.goals
WHERE id = @goal_id::uuid
''';

  /// See [settingsSql].
  static const String badgesSql = '''
SELECT b.team_id::text AS team_id, coalesce(t.name, '') AS team_name,
       b.fill, b.label
FROM publisher.club_badges b
LEFT JOIN football_data.teams t ON t.id = b.team_id
WHERE b.team_id = ANY(string_to_array(@team_ids::text, ',')::uuid[])
''';

  /// See [settingsSql].
  static const String allBadgesSql = '''
SELECT b.team_id::text AS team_id, coalesce(t.name, '') AS team_name,
       b.fill, b.label
FROM publisher.club_badges b
LEFT JOIN football_data.teams t ON t.id = b.team_id
ORDER BY coalesce(t.name, ''), b.team_id
''';

  /// See [settingsSql].
  static const String saveBadgeSql = '''
INSERT INTO publisher.club_badges (team_id, fill, label, updated_at, updated_by)
SELECT t.id, @fill::text, @label::text, now(), @actor::uuid
FROM football_data.teams t
WHERE t.id = @team_id::uuid
ON CONFLICT (team_id) DO UPDATE
SET fill = EXCLUDED.fill, label = EXCLUDED.label, updated_at = now(),
    updated_by = EXCLUDED.updated_by
RETURNING team_id::text AS team_id
''';

  /// See [settingsSql].
  static const String metricsDueSql = '''
SELECT p.id::text AS id, p.platform, p.external_id
FROM publisher.posts p
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
WHERE p.state = 'published'
  AND p.external_id IS NOT NULL
  AND m.post_id IS NULL
  AND p.published_at < @before::timestamptz
  AND p.published_at > @before::timestamptz - interval '7 days'
ORDER BY p.published_at
LIMIT @limit::integer
''';

  /// See [settingsSql].
  static const String saveMetricsSql = '''
INSERT INTO publisher.post_metrics
  (post_id, read_at, reach, reactions, comments, shares, raw)
VALUES (@post_id::uuid, @at::timestamptz, @reach::integer,
        @reactions::integer, @comments::integer, @shares::integer,
        @raw::jsonb)
ON CONFLICT (post_id) DO UPDATE
SET read_at = EXCLUDED.read_at, reach = EXCLUDED.reach,
    reactions = EXCLUDED.reactions, comments = EXCLUDED.comments,
    shares = EXCLUDED.shares, raw = EXCLUDED.raw
''';

  /// See [settingsSql].
  static const String candidatesSql = '''
SELECT s.fixture_id::text AS fixture_id, s.home_team, s.away_team,
       coalesce(l.name, '') AS league_name, s.kickoff_at,
       (c.fixture_id IS NOT NULL AND c.stopped_at IS NULL) AS covered
FROM competition.fixture_schedules s
LEFT JOIN football_data.leagues l ON l.id = s.league_id
LEFT JOIN publisher.coverage c ON c.fixture_id = s.fixture_id
WHERE s.hidden_at IS NULL
  AND NOT s.is_test
  AND s.kickoff_at >= @from::timestamptz
  AND s.kickoff_at < @to::timestamptz
ORDER BY s.kickoff_at, s.home_team
LIMIT 200
''';

  /// See [settingsSql]. Picked again after a stop, the match is read
  /// afresh: the goals of the stop are not posted as news.
  static const String coverSql = '''
INSERT INTO publisher.coverage (fixture_id, added_by, added_at)
SELECT s.fixture_id, @actor::uuid, @at::timestamptz
FROM competition.fixture_schedules s
WHERE s.fixture_id = @fixture_id::uuid
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
RETURNING fixture_id::text AS fixture_id
''';

  /// See [settingsSql].
  static const String stopSql = '''
UPDATE publisher.coverage SET stopped_at = @at::timestamptz
WHERE fixture_id = @fixture_id::uuid AND stopped_at IS NULL
''';

  static const String _postColumns = '''
p.id::text AS id, p.fixture_id::text AS fixture_id,
coalesce(s.home_team || ' - ' || s.away_team, '') AS match_label,
p.kind, p.platform, p.state, p.body, p.card_path, p.external_id, p.error,
p.created_at, p.published_at, p.attempts,
m.reach, m.reactions, m.comments, m.shares''';

  /// See [settingsSql].
  static const String recentPostsSql =
      '''
SELECT $_postColumns
FROM publisher.posts p
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = p.fixture_id
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
ORDER BY p.created_at DESC, p.id
LIMIT @limit::integer
''';

  /// See [settingsSql].
  static const String postSql =
      '''
SELECT $_postColumns
FROM publisher.posts p
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = p.fixture_id
LEFT JOIN publisher.post_metrics m ON m.post_id = p.id
WHERE p.id = @post_id::uuid
''';

  /// See [settingsSql]. Back in the queue, a post is due at once.
  static const String movePostSql = '''
UPDATE publisher.posts
SET state = @to::text,
    updated_at = @at::timestamptz,
    claimed_until = NULL,
    next_attempt_at = NULL,
    not_before = CASE WHEN @to::text = 'queued'
                      THEN least(not_before, @at::timestamptz)
                      ELSE not_before END,
    error = CASE WHEN @to::text = 'queued' THEN NULL ELSE error END
WHERE id = @post_id::uuid
  AND state = ANY(string_to_array(@from::text, ','))
RETURNING id::text AS id
''';

  @override
  Future<Result<Map<PublishPlatform, PlatformIntensity>>> settings() async {
    final read = await _connection.query(settingsSql);
    return read.map((rows) {
      final settings = <PublishPlatform, PlatformIntensity>{
        for (final platform in PublishPlatform.values)
          platform: PlatformIntensity.defaults(platform),
      };
      for (final row in rows) {
        final platform = PublishPlatform.fromWire(_str(row['platform']));
        if (platform == null) {
          continue;
        }
        settings[platform] = PlatformIntensity(
          platform: platform,
          enabled: row['enabled'] == true,
          goals: GoalCoverage.fromWire(_str(row['goals'])) ?? GoalCoverage.all,
          finalResult: row['final_result'] != false,
          hold: Duration(seconds: _int(row['hold_seconds']) ?? 180),
          minGap: Duration(seconds: _int(row['min_gap_seconds']) ?? 0),
          dailyCap: _int(row['daily_cap']) ?? 0,
        );
      }
      return settings;
    });
  }

  @override
  Future<Result<void>> saveSetting(
    PlatformIntensity intensity,
    String actorId,
  ) async {
    final done = await _connection.query(
      saveSettingSql,
      parameters: <String, Object?>{
        'platform': intensity.platform.wire,
        'enabled': intensity.enabled,
        'goals': intensity.goals.wire,
        'final_result': intensity.finalResult,
        'hold': intensity.hold.inSeconds,
        'gap': intensity.minGap.inSeconds,
        'cap': intensity.dailyCap,
        'actor': actorId,
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<List<CoveredFixture>>> activeCoverage({
    required DateTime now,
    required DateTime liveFrom,
  }) async {
    final read = await _connection.query(
      activeCoverageSql,
      parameters: <String, Object?>{
        'now': _iso(now),
        'live_from': _iso(liveFrom),
      },
    );
    return read.map(
      (rows) => <CoveredFixture>[
        for (final row in rows)
          CoveredFixture(
            fixtureId: _str(row['fixture_id']),
            homeName: _str(row['home_team']),
            awayName: _str(row['away_team']),
            homeTeamId: row['home_team_id']?.toString(),
            awayTeamId: row['away_team_id']?.toString(),
            leagueName: _str(row['league_name']),
            kickoffAt: _time(row['kickoff_at']) ?? now,
            known: ScoreLine(
              _int(row['known_home']) ?? 0,
              _int(row['known_away']) ?? 0,
            ),
            knownAt: _time(row['known_at']),
            addedAt: _time(row['added_at']) ?? now,
            finalQueued: row['final_queued'] == true,
            result:
                _int(row['result_home']) == null ||
                    _int(row['result_away']) == null
                ? null
                : ScoreLine(
                    _int(row['result_home'])!,
                    _int(row['result_away'])!,
                  ),
          ),
      ],
    );
  }

  @override
  Future<Result<void>> setKnown(
    String fixtureId,
    ScoreLine score,
    DateTime at,
  ) async {
    final done = await _connection.query(
      setKnownSql,
      parameters: <String, Object?>{
        'fixture_id': fixtureId,
        'home': score.home,
        'away': score.away,
        'at': _iso(at),
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<List<StoredGoal>>> liveGoals(String fixtureId) =>
      _goals(liveGoalsSql, fixtureId);

  @override
  Future<Result<List<StoredGoal>>> confirmedGoals(String fixtureId) =>
      _goals(confirmedGoalsSql, fixtureId);

  Future<Result<List<StoredGoal>>> _goals(String sql, String fixtureId) async {
    final read = await _connection.query(
      sql,
      parameters: <String, Object?>{'fixture_id': fixtureId},
    );
    return read.map((rows) => <StoredGoal>[for (final row in rows) _goal(row)]);
  }

  @override
  Future<Result<void>> addGoal(
    String fixtureId,
    GoalStep step,
    DateTime at, {
    int? feedMinute,
  }) async {
    final done = await _connection.query(
      addGoalSql,
      parameters: <String, Object?>{
        'fixture_id': fixtureId,
        'goal_key': step.key,
        'home': step.home,
        'before_home': step.before.home,
        'before_away': step.before.away,
        'at': _iso(at),
        'feed_minute': feedMinute,
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<StoredGoal?>> withdrawGoal(
    String fixtureId,
    String key,
    DateTime at,
  ) async {
    final read = await _connection.query(
      withdrawGoalSql,
      parameters: <String, Object?>{
        'fixture_id': fixtureId,
        'goal_key': key,
        'at': _iso(at),
      },
    );
    return read.map((rows) => rows.isEmpty ? null : _goal(rows.first));
  }

  @override
  Future<Result<void>> noteDetailsTry(String goalId) async {
    final done = await _connection.query(
      noteDetailsTrySql,
      parameters: <String, Object?>{'goal_id': goalId},
    );
    return done.map((_) {});
  }

  @override
  Future<Result<void>> confirmGoal(
    String goalId, {
    required DateTime at,
    required GoalMoment moment,
    String? scorer,
    String? minuteLabel,
    bool penalty = false,
    bool ownGoal = false,
    String? cardPath,
  }) async {
    final done = await _connection.query(
      confirmGoalSql,
      parameters: <String, Object?>{
        'goal_id': goalId,
        'at': _iso(at),
        'moment': moment.wire,
        'scorer': scorer,
        'minute_label': minuteLabel,
        'penalty': penalty,
        'own_goal': ownGoal,
        'card_path': cardPath,
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<int>> enqueue(List<NewPost> posts) async {
    var added = 0;
    for (final post in posts) {
      final done = await _connection.query(
        enqueueSql,
        parameters: <String, Object?>{
          'dedupe_key': post.dedupeKey,
          'fixture_id': post.fixtureId,
          'goal_id': post.goalId,
          'kind': post.kind.wire,
          'platform': post.platform.wire,
          'state': post.state.wire,
          'body': post.body,
          'card_path': post.cardPath,
          'riyadh_day': isoDay(post.riyadhDay),
          'not_before': _iso(post.notBefore),
        },
      );
      if (done is Err<List<Map<String, dynamic>>>) {
        return Result.err(done.error);
      }
      added += (done as Ok<List<Map<String, dynamic>>>).value.length;
    }
    return Result.ok(added);
  }

  @override
  Future<Result<void>> markFinalQueued(String fixtureId, DateTime at) async {
    final done = await _connection.query(
      markFinalQueuedSql,
      parameters: <String, Object?>{'fixture_id': fixtureId, 'at': _iso(at)},
    );
    return done.map((_) {});
  }

  @override
  Future<Result<List<ClaimedPost>>> claimDue({
    required DateTime now,
    required int limit,
    required Duration lease,
  }) async {
    final cleared = await _connection.query(
      interruptedSql,
      parameters: <String, Object?>{'now': _iso(now)},
    );
    if (cleared is Err<List<Map<String, dynamic>>>) {
      return Result.err(cleared.error);
    }
    final read = await _connection.query(
      claimSql,
      parameters: <String, Object?>{
        'now': _iso(now),
        'until': _iso(now.add(lease)),
        'limit': limit,
      },
    );
    return read.map(
      (rows) => <ClaimedPost>[
        for (final row in rows)
          if (PublishPlatform.fromWire(_str(row['platform']))
              case final platform?)
            ClaimedPost(
              id: _str(row['id']),
              fixtureId: _str(row['fixture_id']),
              goalId: row['goal_id']?.toString(),
              kind: PostKind.fromWire(_str(row['kind'])),
              platform: platform,
              body: _str(row['body']),
              cardPath: row['card_path']?.toString(),
              attempts: _int(row['attempts']) ?? 0,
            ),
      ],
    );
  }

  @override
  Future<Result<void>> finish(
    String postId,
    PostFate fate,
    DateTime at, {
    required bool attempted,
  }) async {
    final (
      String state,
      String? external,
      DateTime? next,
      String? error,
    ) = switch (fate) {
      PostPublished(:final externalId) => (
        PostState.published.wire,
        externalId,
        null,
        null,
      ),
      PostRetry(at: final retryAt, :final reason) => (
        PostState.queued.wire,
        null,
        retryAt,
        reason,
      ),
      PostEnded(state: final ended, :final reason) => (
        ended.wire,
        null,
        null,
        reason,
      ),
    };
    final out =
        state == PostState.published.wire || state == PostState.dryRun.wire;
    final done = await _connection.query(
      finishSql,
      parameters: <String, Object?>{
        'post_id': postId,
        'state': state,
        'external_id': external,
        'next_attempt_at': next == null ? null : _iso(next),
        'error': error == null ? null : _clip(error, 500),
        'published_at': out ? _iso(at) : null,
        'inc': attempted ? 1 : 0,
        'at': _iso(at),
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<({int count, DateTime? lastAt})>> goalPostsOn(
    PublishPlatform platform,
    DateTime riyadhDay,
  ) async {
    final read = await _connection.query(
      goalPostsOnSql,
      parameters: <String, Object?>{
        'platform': platform.wire,
        'riyadh_day': isoDay(riyadhDay),
      },
    );
    return read.map((rows) {
      final row = rows.isEmpty ? const <String, dynamic>{} : rows.first;
      return (count: _int(row['n']) ?? 0, lastAt: _time(row['last_at']));
    });
  }

  @override
  Future<Result<Set<PublishPlatform>>> postedPlatformsOf(String goalId) async {
    final read = await _connection.query(
      postedPlatformsSql,
      parameters: <String, Object?>{'goal_id': goalId},
    );
    return read.map(
      (rows) => <PublishPlatform>{
        for (final row in rows)
          if (PublishPlatform.fromWire(_str(row['platform'])) case final p?) p,
      },
    );
  }

  @override
  Future<Result<bool>> goalStands(String goalId) async {
    final read = await _connection.query(
      goalStandsSql,
      parameters: <String, Object?>{'goal_id': goalId},
    );
    return read.map((rows) => rows.isNotEmpty && rows.first['stands'] == true);
  }

  @override
  Future<Result<Map<String, StoredBadge>>> badges(
    Iterable<String> teamIds,
  ) async {
    final ids = teamIds.where(_uuid.hasMatch).toList();
    if (ids.isEmpty) {
      return const Result.ok(<String, StoredBadge>{});
    }
    final read = await _connection.query(
      badgesSql,
      parameters: <String, Object?>{'team_ids': ids.join(',')},
    );
    return read.map(
      (rows) => <String, StoredBadge>{
        for (final row in rows) _str(row['team_id']): _badge(row),
      },
    );
  }

  @override
  Future<Result<List<MetricsDue>>> metricsDue({
    required DateTime before,
    required int limit,
  }) async {
    final read = await _connection.query(
      metricsDueSql,
      parameters: <String, Object?>{'before': _iso(before), 'limit': limit},
    );
    return read.map(
      (rows) => <MetricsDue>[
        for (final row in rows)
          if (PublishPlatform.fromWire(_str(row['platform'])) case final p?)
            MetricsDue(
              postId: _str(row['id']),
              platform: p,
              externalId: _str(row['external_id']),
            ),
      ],
    );
  }

  @override
  Future<Result<void>> saveMetrics(
    String postId,
    PostMetrics metrics,
    DateTime at,
  ) async {
    String raw;
    try {
      raw = jsonEncode(metrics.raw);
    } on Object {
      raw = '{}';
    }
    final done = await _connection.query(
      saveMetricsSql,
      parameters: <String, Object?>{
        'post_id': postId,
        'at': _iso(at),
        'reach': metrics.reach,
        'reactions': metrics.reactions,
        'comments': metrics.comments,
        'shares': metrics.shares,
        'raw': raw,
      },
    );
    return done.map((_) {});
  }

  @override
  Future<Result<List<CoverageCandidate>>> candidates({
    required DateTime from,
    required DateTime to,
  }) async {
    final read = await _connection.query(
      candidatesSql,
      parameters: <String, Object?>{'from': _iso(from), 'to': _iso(to)},
    );
    return read.map(
      (rows) => <CoverageCandidate>[
        for (final row in rows)
          CoverageCandidate(
            fixtureId: _str(row['fixture_id']),
            homeName: _str(row['home_team']),
            awayName: _str(row['away_team']),
            leagueName: _str(row['league_name']),
            kickoffAt: _time(row['kickoff_at']) ?? from,
            covered: row['covered'] == true,
          ),
      ],
    );
  }

  @override
  Future<Result<bool>> cover(
    String fixtureId,
    String actorId,
    DateTime at,
  ) async {
    final read = await _connection.query(
      coverSql,
      parameters: <String, Object?>{
        'fixture_id': fixtureId,
        'actor': actorId,
        'at': _iso(at),
      },
    );
    return read.map((rows) => rows.isNotEmpty);
  }

  @override
  Future<Result<void>> stopCovering(String fixtureId, DateTime at) async {
    final done = await _connection.query(
      stopSql,
      parameters: <String, Object?>{'fixture_id': fixtureId, 'at': _iso(at)},
    );
    return done.map((_) {});
  }

  @override
  Future<Result<List<PostView>>> recentPosts({required int limit}) async {
    final read = await _connection.query(
      recentPostsSql,
      parameters: <String, Object?>{'limit': limit},
    );
    return read.map(
      (rows) => <PostView>[
        for (final row in rows)
          if (_postView(row) case final view?) view,
      ],
    );
  }

  @override
  Future<Result<PostView?>> post(String postId) async {
    final read = await _connection.query(
      postSql,
      parameters: <String, Object?>{'post_id': postId},
    );
    return read.map((rows) => rows.isEmpty ? null : _postView(rows.first));
  }

  @override
  Future<Result<bool>> movePost(
    String postId, {
    required Set<PostState> from,
    required PostState to,
    required DateTime at,
  }) async {
    final read = await _connection.query(
      movePostSql,
      parameters: <String, Object?>{
        'post_id': postId,
        'to': to.wire,
        'at': _iso(at),
        'from': from.map((state) => state.wire).join(','),
      },
    );
    return read.map((rows) => rows.isNotEmpty);
  }

  @override
  Future<Result<List<StoredBadge>>> allBadges() async {
    final read = await _connection.query(allBadgesSql);
    return read.map(
      (rows) => <StoredBadge>[for (final row in rows) _badge(row)],
    );
  }

  @override
  Future<Result<bool>> saveBadge(
    String teamId, {
    required String fill,
    required String? label,
    required String actorId,
  }) async {
    final read = await _connection.query(
      saveBadgeSql,
      parameters: <String, Object?>{
        'team_id': teamId,
        'fill': fill,
        'label': label,
        'actor': actorId,
      },
    );
    return read.map((rows) => rows.isNotEmpty);
  }

  static StoredGoal _goal(Map<String, dynamic> row) => StoredGoal(
    id: _str(row['id']),
    fixtureId: _str(row['fixture_id']),
    step: GoalStep(
      home: row['home'] == true,
      before: ScoreLine(
        _int(row['before_home']) ?? 0,
        _int(row['before_away']) ?? 0,
      ),
    ),
    state: StoredGoalState.fromWire(_str(row['state'])),
    firstSeenAt: _time(row['first_seen_at']) ?? DateTime.utc(1970),
    feedMinute: _int(row['feed_minute']),
    moment: row['moment'] == null
        ? null
        : GoalMoment.fromWire(row['moment'].toString()),
    scorer: row['scorer']?.toString(),
    minuteLabel: row['minute_label']?.toString(),
    penalty: row['penalty'] == true,
    ownGoal: row['own_goal'] == true,
    detailsTries: _int(row['details_tries']) ?? 0,
    cardPath: row['card_path']?.toString(),
  );

  static StoredBadge _badge(Map<String, dynamic> row) => StoredBadge(
    teamId: _str(row['team_id']),
    teamName: _str(row['team_name']),
    fill: _str(row['fill']),
    label: row['label']?.toString(),
  );

  static PostView? _postView(Map<String, dynamic> row) {
    final platform = PublishPlatform.fromWire(_str(row['platform']));
    final created = _time(row['created_at']);
    if (platform == null || created == null) {
      return null;
    }
    return PostView(
      id: _str(row['id']),
      fixtureId: _str(row['fixture_id']),
      matchLabel: _str(row['match_label']),
      kind: PostKind.fromWire(_str(row['kind'])),
      platform: platform,
      state: PostState.fromWire(_str(row['state'])),
      body: _str(row['body']),
      cardPath: row['card_path']?.toString(),
      externalId: row['external_id']?.toString(),
      error: row['error']?.toString(),
      createdAt: created,
      publishedAt: _time(row['published_at']),
      attempts: _int(row['attempts']) ?? 0,
      reach: _int(row['reach']),
      reactions: _int(row['reactions']),
      comments: _int(row['comments']),
      shares: _int(row['shares']),
    );
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _iso(DateTime at) => at.toUtc().toIso8601String();

  static String _str(Object? value) => value?.toString() ?? '';

  static int? _int(Object? value) => value is int ? value : null;

  static DateTime? _time(Object? value) =>
      value is DateTime ? value.toUtc() : null;

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
