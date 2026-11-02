import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [MonthCrownStore] (migration 0199, script 204).
///
/// The months, their state, the results to score again and the prize come
/// from the migration's read-only functions, read uncached: a crowning must
/// never stand on a figure held in memory. The prize set ahead and the
/// notices are the two tables of 0199. The database refuses a prize for a
/// crowned month (`champion.already_crowned`) or a month that does not
/// exist (`champion.month_not_found`).
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresMonthCrownStore implements MonthCrownStore {
  /// Creates the store over [_connection].
  const PostgresMonthCrownStore(this._connection);

  final PostgresConnection _connection;

  /// The months that ended within the window.
  static const String dueSql = '''
SELECT season_id::text AS season_id, label, end_at, crowned_at
FROM competition.month_crown_due(@now::timestamptz,
                                 make_interval(hours => @window_hours::int))
''';

  /// Where one month stands.
  static const String stateSql = '''
SELECT waiting, waiting_names, skipped, skipped_names, last_result_at, rescore
FROM competition.month_crown_state(@season_id::uuid, @now::timestamptz,
                                   make_interval(hours => @postponed_hours::int))
''';

  /// The month's results whose points are not all in.
  static const String rescoreSql = '''
SELECT fixture_id::text AS fixture_id
FROM competition.month_crown_rescore(@season_id::uuid)
''';

  /// The prize to crown the month with.
  static const String prizeSql = '''
SELECT competition.month_prize_for(@season_id::uuid) AS prize
''';

  /// Sets or replaces the prize set ahead.
  static const String setPrizeSql = '''
INSERT INTO competition.month_prizes (season_id, prize, set_by, set_at)
VALUES (@season_id::uuid, @prize::text, @set_by::uuid, @set_at::timestamptz)
ON CONFLICT (season_id) DO UPDATE SET
  prize  = EXCLUDED.prize,
  set_by = EXCLUDED.set_by,
  set_at = EXCLUDED.set_at
''';

  /// Records a notice once; a row back means it is new.
  static const String noticeSql = '''
INSERT INTO competition.month_crown_notices (season_id, kind, signature)
VALUES (@season_id::uuid, @kind::text, @signature::text)
ON CONFLICT DO NOTHING
RETURNING kind
''';

  /// The latest result write after the crowning.
  static const String changedSql = '''
SELECT competition.month_results_after(@season_id::uuid, @since::timestamptz)
  AS written_at
''';

  @override
  Future<Result<List<CrownDueMonth>>> dueMonths({
    required DateTime now,
    required Duration window,
  }) async {
    final result = await _connection.query(
      dueSql,
      parameters: {'now': now.toUtc(), 'window_hours': window.inHours},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <CrownDueMonth>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? seasonId = row['season_id'];
      final Object? label = row['label'];
      final Object? endAt = row['end_at'];
      final Object? crownedAt = row['crowned_at'];
      if (seasonId is! String || label is! String || endAt is! DateTime) {
        return Result.err(_corrupt('month'));
      }
      out.add(
        CrownDueMonth(
          seasonId: SeasonId(seasonId),
          label: label,
          endAt: endAt.toUtc(),
          crownedAt: crownedAt is DateTime ? crownedAt.toUtc() : null,
        ),
      );
    }
    return Result.ok(List<CrownDueMonth>.unmodifiable(out));
  }

  @override
  Future<Result<MonthCrownState>> stateOf({
    required SeasonId season,
    required DateTime now,
    required Duration postponedAfter,
  }) async {
    final result = await _connection.query(
      stateSql,
      parameters: {
        'season_id': season.value,
        'now': now.toUtc(),
        'postponed_hours': postponedAfter.inHours,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return Result.err(_corrupt('state'));
    }
    final row = rows.first;
    final int? waiting = _int(row['waiting']);
    final int? skipped = _int(row['skipped']);
    final int? rescore = _int(row['rescore']);
    if (waiting == null || skipped == null || rescore == null) {
      return Result.err(_corrupt('state'));
    }
    final Object? lastResultAt = row['last_result_at'];
    return Result.ok(
      MonthCrownState(
        waiting: waiting,
        waitingNames: row['waiting_names'] as String?,
        skipped: skipped,
        skippedNames: row['skipped_names'] as String?,
        lastResultAt: lastResultAt is DateTime ? lastResultAt.toUtc() : null,
        rescore: rescore,
      ),
    );
  }

  @override
  Future<Result<List<FixtureRef>>> toRescore(SeasonId season) async {
    final result = await _connection.query(
      rescoreSql,
      parameters: {'season_id': season.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <FixtureRef>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? fixtureId = row['fixture_id'];
      if (fixtureId is! String) {
        return Result.err(_corrupt('fixture'));
      }
      out.add(FixtureRef(fixtureId));
    }
    return Result.ok(List<FixtureRef>.unmodifiable(out));
  }

  @override
  Future<Result<String?>> prizeFor(SeasonId season) async {
    final result = await _connection.query(
      prizeSql,
      parameters: {'season_id': season.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? prize = rows.isEmpty ? null : rows.first['prize'];
    return Result.ok(prize is String ? prize : null);
  }

  @override
  Future<Result<void>> setPrize({
    required SeasonId season,
    required String prize,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    final result = await _connection.query(
      setPrizeSql,
      parameters: {
        'season_id': season.value,
        'prize': prize,
        'set_by': setBy.value,
        'set_at': setAt.toUtc(),
      },
    );
    return switch (result) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _prizeRefusal(error),
      ),
    };
  }

  @override
  Future<Result<bool>> noteOnce({
    required SeasonId season,
    required String kind,
    required String signature,
  }) async {
    final result = await _connection.query(
      noticeSql,
      parameters: {
        'season_id': season.value,
        'kind': kind,
        'signature': signature,
      },
    );
    return switch (result) {
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }

  @override
  Future<Result<DateTime?>> resultsWrittenAfter({
    required SeasonId season,
    required DateTime since,
  }) async {
    final result = await _connection.query(
      changedSql,
      parameters: {'season_id': season.value, 'since': since.toUtc()},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? writtenAt = rows.isEmpty ? null : rows.first['written_at'];
    return Result.ok(writtenAt is DateTime ? writtenAt.toUtc() : null);
  }

  /// The 0199 refusals of a prize, in the admin's words.
  static AppError _prizeRefusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    return switch (cause.constraintName ?? '') {
      'month_prizes_not_crowned' => const AppError.invariant(
        'champion.already_crowned',
        'هذا الشهر متوَّج مسبقًا',
      ),
      'month_prizes_season_fkey' => const AppError.invariant(
        'champion.month_not_found',
        'الشهر غير موجود',
      ),
      'month_prizes_prize_check' => const AppError.validation(
        'champion.prize_blank',
        'اكتب الجائزة',
      ),
      _ => error,
    };
  }

  static AppError _corrupt(String what) => AppError.transient(
    'champion.row_corrupt',
    'a month crown $what could not be read',
  );

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final BigInt v => v.toInt(),
    _ => null,
  };
}
