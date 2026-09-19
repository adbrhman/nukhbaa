import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [DailyChallengeRepository].
///
/// One statement answers both halves of the question, so the prediction path
/// pays a single round trip for it: the LEFT JOIN counts the day's fixtures
/// and the participant's predictions over the same rows, and `count(fp.id)`
/// counts only the matched ones.
///
/// `AT TIME ZONE 'Asia/Riyadh'` is the same day boundary migration 0054's
/// `daily_active_users` view uses and the same one `riyadhDayOf` computes in
/// Dart; Riyadh has no daylight saving, so the fixed +3 offset and the named
/// zone agree on every date.
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter (Security ADR §2).
final class PostgresDailyChallengeRepository
    implements DailyChallengeRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresDailyChallengeRepository(this._connection);

  final PostgresConnection _connection;

  static const String _progressSql = '''
SELECT
  count(*)     AS total,
  count(fp.id) AS predicted
FROM competition.season_fixtures sf
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = sf.fixture_id
 AND fp.participant_id = @participant_id
WHERE sf.season_id = @season_id
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @day::date
''';

  @override
  Future<Result<DailyChallengeProgress>> progressOn({
    required SeasonId seasonId,
    required ParticipantId participantId,
    required DateTime day,
  }) async {
    final utcDay = day.toUtc();
    final isoDay =
        '${utcDay.year.toString().padLeft(4, '0')}-'
        '${utcDay.month.toString().padLeft(2, '0')}-'
        '${utcDay.day.toString().padLeft(2, '0')}';

    final result = await _connection.query(
      _progressSql,
      parameters: {
        'season_id': seasonId.value,
        'participant_id': participantId.value,
        'day': isoDay,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty
            // An aggregate always returns one row; an empty result would mean
            // a driver surprise, and "no fixtures" is the honest reading.
            ? const DailyChallengeProgress(total: 0, predicted: 0)
            : DailyChallengeProgress(
                total: _count(value.first['total']),
                predicted: _count(value.first['predicted']),
              ),
      ),
    };
  }

  /// `count(*)` may arrive as an int or, under a text-codec projection, as a
  /// BigInt-backed string. Mirrors `_mapCount` in the fixture-prediction
  /// adapter: a cast would throw, and this adapter is total.
  static int _count(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
