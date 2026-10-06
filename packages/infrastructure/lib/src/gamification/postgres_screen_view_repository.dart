import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ScreenViewRepository] (migration 0093).
///
/// One statement per report, whatever its size: the screens and their
/// counts travel as two parallel arrays (`unnest`), and a screen already
/// counted that day is summed into its row. The explicit `::text[]` and
/// `::int[]` casts are required, as for every array this driver binds.
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter.
final class PostgresScreenViewRepository implements ScreenViewRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresScreenViewRepository(this._connection);

  final PostgresConnection _connection;

  /// The statement `supabase/tests/0093_screen_views_test.sql` runs, with
  /// its parameters inlined.
  static const String upsertSql = '''
INSERT INTO gamification.screen_views
  (view_date, screen, user_id, opens, first_at, last_at)
SELECT @view_date::date, s.screen, @user_id::uuid, s.opens,
       @reported_at::timestamptz, @reported_at::timestamptz
FROM unnest(@screens::text[], @opens::int[]) AS s(screen, opens)
ON CONFLICT (view_date, screen, user_id) DO UPDATE SET
  opens = LEAST(gamification.screen_views.opens + EXCLUDED.opens, 100000),
  last_at = EXCLUDED.last_at
''';

  @override
  Future<Result<void>> add({
    required UserId userId,
    required DateTime day,
    required Map<String, int> opens,
    required DateTime reportedAt,
  }) async {
    if (opens.isEmpty) {
      return const Result.ok(null);
    }
    final List<String> screens = opens.keys.toList();
    final result = await _connection.query(
      upsertSql,
      parameters: {
        'view_date': isoDay(day),
        'user_id': userId.value,
        'reported_at': reportedAt.toUtc(),
        'screens': screens,
        'opens': [for (final String s in screens) opens[s]!],
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }
}
