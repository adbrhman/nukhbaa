import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hCupStore] (NK185, migration 0190).
///
/// **A stage's fixtures** are read the way a round's are
/// (`PostgresH2hSheetReader`): its frozen list less every fixture that left
/// the stage's day, was hidden, is a test fixture, or had no result by the
/// end of the Riyadh day after the stage's day. A player's figures are his
/// stored scores and predictions on those fixtures, over every
/// participation he holds.
///
/// Every write is append-only; entries, results and titles are inserted
/// with `ON CONFLICT DO NOTHING`, so a repeated run changes nothing. The
/// database's refusals of a stage (before the 19 rounds, out of order, a
/// day already taken) arrive as constraint violations named `h2h_cup_...`
/// and are returned as the invariant `h2h.cup_refused`.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hCupStore implements H2hCupStore {
  /// Creates the store over [_connection].
  const PostgresH2hCupStore(this._connection);

  final PostgresConnection _connection;

  /// The qualifiers of a month.
  static const String entriesSql = '''
SELECT e.user_id::text AS user_id, e.place, e.group_number,
       e.league_points, e.points_for, e.exact_count
FROM gamification.h2h_cup_entries e
WHERE e.month_start = @month::date
ORDER BY e.place, e.group_number
''';

  /// The stages of a month, in day order, with their freeze.
  static const String stagesSql = '''
SELECT s.id::text AS id, s.place, s.stage, s.attempt,
       to_char(s.day, 'YYYY-MM-DD') AS day,
       COALESCE(k.fixture_count, s.fixture_count)::integer AS fixture_count,
       k.locked_at
FROM gamification.h2h_cup_stages s
LEFT JOIN gamification.h2h_cup_stage_locks k ON k.stage_id = s.id
WHERE s.month_start = @month::date
ORDER BY s.day
''';

  /// The pairs of a month's stages, with their results once decided.
  static const String pairsSql = '''
SELECT p.stage_id::text AS stage_id, p.slot,
       p.home_user::text AS home_user, p.away_user::text AS away_user,
       r.outcome, r.winner_user::text AS winner_user,
       r.home_points, r.away_points, r.home_exact, r.away_exact,
       r.home_predicted, r.away_predicted
FROM gamification.h2h_cup_pairs p
JOIN gamification.h2h_cup_stages s ON s.id = p.stage_id
LEFT JOIN gamification.h2h_cup_results r
  ON r.stage_id = p.stage_id AND r.slot = p.slot
WHERE s.month_start = @month::date
ORDER BY p.stage_id, p.slot
''';

  /// The titles of a month.
  static const String titlesSql = '''
SELECT t.place, t.champion::text AS champion, t.runner_up::text AS runner_up,
       t.how
FROM gamification.h2h_cup_titles t
WHERE t.month_start = @month::date
ORDER BY t.place
''';

  /// One qualifier; a stored one stays.
  static const String enterSql = '''
INSERT INTO gamification.h2h_cup_entries
  (month_start, place, user_id, group_number, league_points, points_for,
   exact_count)
VALUES (@month::date, @place::smallint, @user_id::uuid,
        @group_number::smallint, @league_points::integer,
        @points_for::integer, @exact_count::integer)
ON CONFLICT DO NOTHING
''';

  /// One stage on its day.
  static const String stageSql = '''
INSERT INTO gamification.h2h_cup_stages
  (id, month_start, place, stage, attempt, day, fixture_count)
VALUES (@id::uuid, @month::date, @place::smallint, @stage, @attempt::smallint,
        @day::date, @fixture_count::smallint)
''';

  /// One pair of a stage.
  static const String pairSql = '''
INSERT INTO gamification.h2h_cup_pairs (stage_id, slot, home_user, away_user)
VALUES (@stage_id::uuid, @slot::smallint, @home::uuid, @away::uuid)
''';

  /// Freezes a stage's fixtures: every visible, non-test fixture of its day,
  /// once.
  static const String freezeSql = '''
INSERT INTO gamification.h2h_cup_stage_fixtures (stage_id, fixture_id)
SELECT DISTINCT @stage_id::uuid, fs.fixture_id
FROM competition.fixture_schedules fs
WHERE fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND EXISTS (
    SELECT 1 FROM competition.season_fixtures sf
    WHERE sf.fixture_id = fs.fixture_id
  )
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @day::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_cup_stage_locks k
    WHERE k.stage_id = @stage_id::uuid
  )
ON CONFLICT (stage_id, fixture_id) DO NOTHING
''';

  /// Marks the stage frozen with its count, once.
  static const String lockSql = '''
INSERT INTO gamification.h2h_cup_stage_locks (stage_id, fixture_count)
SELECT @stage_id::uuid, count(*)::smallint
FROM gamification.h2h_cup_stage_fixtures
WHERE stage_id = @stage_id::uuid
ON CONFLICT (stage_id) DO NOTHING
''';

  /// The frozen count of a stage.
  static const String lockedCountSql = '''
SELECT fixture_count
FROM gamification.h2h_cup_stage_locks
WHERE stage_id = @stage_id::uuid
''';

  /// How many of a stage's fixtures are still in play, and how many of them
  /// are settled.
  static const String countsSql = '''
WITH st AS (
  SELECT s.id, s.day FROM gamification.h2h_cup_stages s
  WHERE s.id = @stage_id::uuid
),
valid AS (
  SELECT f.fixture_id
  FROM st
  JOIN gamification.h2h_cup_stage_fixtures f ON f.stage_id = st.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = f.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = f.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = st.day
    AND (rr.created_at < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
)
SELECT count(v.fixture_id)::integer AS fixtures,
       count(v.fixture_id) FILTER (
         WHERE res.fixture_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM scoring.fixture_scores sp
             WHERE sp.fixture_id = v.fixture_id AND sp.grade = 'pending'
           ))::integer AS settled
FROM valid v
LEFT JOIN scoring.fixture_results res ON res.fixture_id = v.fixture_id
''';

  /// Each paired player's points, exact scorelines and predictions on the
  /// stage's fixtures still in play. A suspended account counts none of
  /// them, so it is absent and its opponent goes through on a walkover
  /// (decided by the owner 2026-11-01: no reward while suspended).
  static const String sidesSql = '''
WITH st AS (
  SELECT s.id, s.day FROM gamification.h2h_cup_stages s
  WHERE s.id = @stage_id::uuid
),
valid AS (
  SELECT f.fixture_id
  FROM st
  JOIN gamification.h2h_cup_stage_fixtures f ON f.stage_id = st.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = f.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = f.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = st.day
    AND (rr.created_at < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
),
players AS (
  SELECT p.home_user AS user_id FROM gamification.h2h_cup_pairs p
  WHERE p.stage_id = @stage_id::uuid
  UNION
  SELECT p.away_user FROM gamification.h2h_cup_pairs p
  WHERE p.stage_id = @stage_id::uuid
)
SELECT pl.user_id::text                                    AS user_id,
       COALESCE(sum(s.points), 0)::integer                 AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer       AS exact_count,
       count(fp.id)::integer                               AS predicted_count
FROM players pl
JOIN competition.participants p ON p.user_id = pl.user_id
JOIN identity.users u ON u.id = pl.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN valid v ON v.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = v.fixture_id AND fp.participant_id = p.id
  AND u.status <> 'suspended' AND u.hidden_at IS NULL
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = v.fixture_id AND s.participant_id = p.id
  AND u.status <> 'suspended' AND u.hidden_at IS NULL
GROUP BY pl.user_id
''';

  /// One pair's decision; a stored one stays.
  static const String resultSql = '''
INSERT INTO gamification.h2h_cup_results
  (stage_id, slot, winner_user, outcome, home_points, away_points,
   home_exact, away_exact, home_predicted, away_predicted)
VALUES (@stage_id::uuid, @slot::smallint, @winner::uuid, @outcome,
        @home_points::integer, @away_points::integer, @home_exact::integer,
        @away_exact::integer, @home_predicted::integer,
        @away_predicted::integer)
ON CONFLICT DO NOTHING
''';

  /// A path's title; a stored one stays.
  static const String titleSql = '''
INSERT INTO gamification.h2h_cup_titles
  (month_start, place, champion, runner_up, how)
VALUES (@month::date, @place::smallint, @champion::uuid, @runner_up::uuid,
        @how)
ON CONFLICT DO NOTHING
''';

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    final params = {'month': _isoDay(monthStart)};
    final entriesResult = await _connection.query(
      entriesSql,
      parameters: params,
    );
    if (entriesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(entriesResult.error);
    }
    final entries = <H2hCupEntry>[];
    for (final row in (entriesResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final place = _int(row['place']);
      final group = _int(row['group_number']);
      final league = _int(row['league_points']);
      final points = _int(row['points_for']);
      final exact = _int(row['exact_count']);
      if (user is Err<UserId> ||
          place == null ||
          group == null ||
          league == null ||
          points == null ||
          exact == null) {
        return Result.err(_corrupt('entry'));
      }
      entries.add(
        H2hCupEntry(
          userId: (user as Ok<UserId>).value,
          place: place,
          groupNumber: group,
          leaguePoints: league,
          pointsFor: points,
          exactCount: exact,
        ),
      );
    }

    final pairsResult = await _connection.query(pairsSql, parameters: params);
    if (pairsResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(pairsResult.error);
    }
    final pairs = <String, List<H2hCupPair>>{};
    final results = <String, List<H2hCupResult>>{};
    for (final row in (pairsResult as Ok<List<Map<String, dynamic>>>).value) {
      final stage = row['stage_id']?.toString() ?? '';
      final slot = _int(row['slot']);
      final home = UserId.tryParse(row['home_user']?.toString());
      final away = UserId.tryParse(row['away_user']?.toString());
      if (slot == null || home is Err<UserId> || away is Err<UserId>) {
        return Result.err(_corrupt('pair'));
      }
      (pairs[stage] ??= <H2hCupPair>[]).add(
        H2hCupPair(
          slot: slot,
          home: (home as Ok<UserId>).value,
          away: (away as Ok<UserId>).value,
        ),
      );
      final outcome = row['outcome']?.toString();
      if (outcome == null) {
        continue;
      }
      final winnerRaw = row['winner_user']?.toString();
      UserId? winner;
      if (winnerRaw != null) {
        final parsed = UserId.tryParse(winnerRaw);
        if (parsed is Err<UserId>) {
          return Result.err(_corrupt('result'));
        }
        winner = (parsed as Ok<UserId>).value;
      }
      (results[stage] ??= <H2hCupResult>[]).add(
        H2hCupResult(
          slot: slot,
          winner: winner,
          outcome: outcome,
          home: H2hCupSide(
            points: _int(row['home_points']) ?? 0,
            exact: _int(row['home_exact']) ?? 0,
            predicted: _int(row['home_predicted']) ?? 0,
          ),
          away: H2hCupSide(
            points: _int(row['away_points']) ?? 0,
            exact: _int(row['away_exact']) ?? 0,
            predicted: _int(row['away_predicted']) ?? 0,
          ),
        ),
      );
    }

    final stagesResult = await _connection.query(stagesSql, parameters: params);
    if (stagesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(stagesResult.error);
    }
    final stages = <H2hCupStage>[];
    for (final row in (stagesResult as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hCupStageId.tryParse(row['id']?.toString());
      final place = _int(row['place']);
      final round = H2hCupRound.fromWire(row['stage']?.toString() ?? '');
      final attempt = _int(row['attempt']);
      final day = _day(row['day']);
      final count = _int(row['fixture_count']);
      if (id is Err<H2hCupStageId> ||
          place == null ||
          round == null ||
          attempt == null ||
          day == null ||
          count == null) {
        return Result.err(_corrupt('stage'));
      }
      final stageId = (id as Ok<H2hCupStageId>).value;
      stages.add(
        H2hCupStage(
          id: stageId,
          monthStart: monthStart,
          step: H2hCupStep(place, round),
          attempt: attempt,
          day: day,
          fixtureCount: count,
          lockedAt: _timestamp(row['locked_at']),
          pairs: List.unmodifiable(pairs[stageId.value] ?? const []),
          results: List.unmodifiable(results[stageId.value] ?? const []),
        ),
      );
    }

    final titlesResult = await _connection.query(titlesSql, parameters: params);
    if (titlesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(titlesResult.error);
    }
    final titles = <H2hCupTitle>[];
    for (final row in (titlesResult as Ok<List<Map<String, dynamic>>>).value) {
      final place = _int(row['place']);
      final champion = _optionalUser(row['champion']);
      final runnerUp = _optionalUser(row['runner_up']);
      if (place == null || champion == _bad || runnerUp == _bad) {
        return Result.err(_corrupt('title'));
      }
      titles.add(
        H2hCupTitle(
          place: place,
          champion: champion,
          runnerUp: runnerUp,
          how: row['how']?.toString() ?? 'vacant',
        ),
      );
    }

    return Result.ok(
      H2hCupState(entries: entries, stages: stages, titles: titles),
    );
  }

  @override
  Future<Result<void>> enter(DateTime monthStart, List<H2hCupEntry> entries) {
    return _connection.runInTransaction<void>((tx) async {
      for (final e in entries) {
        final inserted = await tx.query(
          enterSql,
          parameters: {
            'month': _isoDay(monthStart),
            'place': e.place,
            'user_id': e.userId.value,
            'group_number': e.groupNumber,
            'league_points': e.leaguePoints,
            'points_for': e.pointsFor,
            'exact_count': e.exactCount,
          },
        );
        if (inserted is Err<List<Map<String, dynamic>>>) {
          return Result.err(inserted.error);
        }
      }
      return const Result.ok(null);
    });
  }

  @override
  Future<Result<void>> schedule({
    required H2hCupStageId id,
    required DateTime monthStart,
    required H2hCupStep step,
    required int attempt,
    required DateTime day,
    required int fixtureCount,
    required List<H2hCupPair> pairs,
  }) async {
    final result = await _connection.runInTransaction<void>((tx) async {
      final stage = await tx.query(
        stageSql,
        parameters: {
          'id': id.value,
          'month': _isoDay(monthStart),
          'place': step.place,
          'stage': step.round.wire,
          'attempt': attempt,
          'day': _isoDay(day),
          'fixture_count': fixtureCount,
        },
      );
      if (stage is Err<List<Map<String, dynamic>>>) {
        return Result.err(stage.error);
      }
      for (final pair in pairs) {
        final inserted = await tx.query(
          pairSql,
          parameters: {
            'stage_id': id.value,
            'slot': pair.slot,
            'home': pair.home.value,
            'away': pair.away.value,
          },
        );
        if (inserted is Err<List<Map<String, dynamic>>>) {
          return Result.err(inserted.error);
        }
      }
      return const Result.ok(null);
    });
    return switch (result) {
      Ok<void>() => const Result.ok(null),
      Err<void>(:final error) => Result.err(_refusal(error)),
    };
  }

  @override
  Future<Result<int>> lock({
    required H2hCupStageId stageId,
    required DateTime day,
  }) {
    return _connection.runInTransaction<int>((tx) async {
      final params = {'stage_id': stageId.value};
      final frozen = await tx.query(
        freezeSql,
        parameters: {...params, 'day': _isoDay(day)},
      );
      if (frozen is Err<List<Map<String, dynamic>>>) {
        return Result.err(frozen.error);
      }
      final locked = await tx.query(lockSql, parameters: params);
      if (locked is Err<List<Map<String, dynamic>>>) {
        return Result.err(locked.error);
      }
      final count = await tx.query(lockedCountSql, parameters: params);
      if (count is Err<List<Map<String, dynamic>>>) {
        return Result.err(count.error);
      }
      final rows = (count as Ok<List<Map<String, dynamic>>>).value;
      return Result.ok(
        rows.isEmpty ? 0 : _int(rows.first['fixture_count']) ?? 0,
      );
    });
  }

  @override
  Future<Result<H2hCupStageFigures>> figuresOf(H2hCupStageId stageId) async {
    final params = {'stage_id': stageId.value};
    final countsResult = await _connection.query(countsSql, parameters: params);
    if (countsResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(countsResult.error);
    }
    final counts = (countsResult as Ok<List<Map<String, dynamic>>>).value;
    final fixtures = counts.isEmpty ? 0 : _int(counts.first['fixtures']) ?? 0;
    final settled = counts.isEmpty ? 0 : _int(counts.first['settled']) ?? 0;

    final sidesResult = await _connection.query(sidesSql, parameters: params);
    if (sidesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(sidesResult.error);
    }
    final sides = <UserId, H2hCupSide>{};
    for (final row in (sidesResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final points = _int(row['points']);
      final exact = _int(row['exact_count']);
      final predicted = _int(row['predicted_count']);
      if (user is Err<UserId> ||
          points == null ||
          exact == null ||
          predicted == null) {
        return Result.err(_corrupt('side'));
      }
      sides[(user as Ok<UserId>).value] = H2hCupSide(
        points: points,
        exact: exact,
        predicted: predicted,
      );
    }
    return Result.ok(
      H2hCupStageFigures(fixtures: fixtures, settled: settled, sides: sides),
    );
  }

  @override
  Future<Result<void>> decide({
    required H2hCupStageId stageId,
    required List<H2hCupResult> results,
  }) {
    return _connection.runInTransaction<void>((tx) async {
      for (final r in results) {
        final inserted = await tx.query(
          resultSql,
          parameters: {
            'stage_id': stageId.value,
            'slot': r.slot,
            'winner': r.winner?.value,
            'outcome': r.outcome,
            'home_points': r.home.points,
            'away_points': r.away.points,
            'home_exact': r.home.exact,
            'away_exact': r.away.exact,
            'home_predicted': r.home.predicted,
            'away_predicted': r.away.predicted,
          },
        );
        if (inserted is Err<List<Map<String, dynamic>>>) {
          return Result.err(inserted.error);
        }
      }
      return const Result.ok(null);
    });
  }

  @override
  Future<Result<void>> crown({
    required DateTime monthStart,
    required int place,
    required UserId? champion,
    required UserId? runnerUp,
    required String how,
  }) async {
    final inserted = await _connection.query(
      titleSql,
      parameters: {
        'month': _isoDay(monthStart),
        'place': place,
        'champion': champion?.value,
        'runner_up': runnerUp?.value,
        'how': how,
      },
    );
    return switch (inserted) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }

  /// The 0190 refusals of a stage: one invariant code for the job.
  static AppError _refusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final name = cause.constraintName ?? '';
    if (name.startsWith('h2h_cup_')) {
      return AppError.invariant(
        'h2h.cup_refused',
        'The cup stage was refused: $name',
      );
    }
    return error;
  }

  static const UserId _bad = UserId('00000000-0000-0000-0000-000000000000');

  static UserId? _optionalUser(Object? raw) {
    if (raw == null) {
      return null;
    }
    final parsed = UserId.tryParse(raw.toString());
    return parsed is Ok<UserId> ? parsed.value : _bad;
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored Elite Cup $what row could not be read',
  );

  static int? _int(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  static DateTime? _day(Object? raw) {
    final text = raw?.toString();
    if (text == null) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
