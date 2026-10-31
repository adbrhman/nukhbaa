import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [MonthPodiumRepository] (migration 0191).
///
/// A podium is set in one transaction: every place of the month or none.
/// The database refuses a podium for a month not crowned, a champion on it,
/// a player who did not play the month, or a place already set; those
/// refusals are returned as the invariant `champion.podium_refused`. The
/// pictures are written through `PostgresMonthChampionRepository.setPhoto`,
/// which covers the podium too.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresMonthPodiumRepository implements MonthPodiumRepository {
  /// Creates the repository over [_connection].
  const PostgresMonthPodiumRepository(this._connection);

  final PostgresConnection _connection;

  static const String _columns = '''
SELECT p.season_id::text AS season_id,
       p.place,
       p.user_id::text AS user_id,
       u.display_name,
       p.points,
       p.exact_count,
       p.decided_count,
       p.photo_updated_at,
       u.avatar_updated_at
FROM competition.month_podium p
JOIN competition.seasons s ON s.id = p.season_id
JOIN identity.users u ON u.id = p.user_id
''';

  /// Every podium, newest month first, then by place.
  static const String listSql =
      '${_columns}ORDER BY s.end_at DESC, p.place\nLIMIT @limit::int\n';

  /// One month's podium, by place.
  static const String ofSql =
      '${_columns}WHERE p.season_id = @season_id::uuid\nORDER BY p.place\n';

  /// One place.
  static const String setSql = '''
INSERT INTO competition.month_podium
  (season_id, place, user_id, points, exact_count, decided_count, set_at,
   set_by)
VALUES
  (@season_id::uuid, @place::smallint, @user_id::uuid, @points::int,
   @exact_count::int, @decided_count::int, @set_at::timestamptz,
   @set_by::uuid)
''';

  @override
  Future<Result<List<MonthPodiumPlace>>> list({required int limit}) =>
      _read(listSql, {'limit': limit});

  @override
  Future<Result<List<MonthPodiumPlace>>> of(SeasonId season) =>
      _read(ofSql, {'season_id': season.value});

  @override
  Future<Result<void>> set({
    required SeasonId season,
    required List<PodiumPlaceToSet> places,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    final result = await _connection.runInTransaction<void>((tx) async {
      for (final place in places) {
        final inserted = await tx.query(
          setSql,
          parameters: {
            'season_id': season.value,
            'place': place.place,
            'user_id': place.userId.value,
            'points': place.points,
            'exact_count': place.exactCount,
            'decided_count': place.decidedCount,
            'set_at': setAt.toUtc(),
            'set_by': setBy.value,
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

  Future<Result<List<MonthPodiumPlace>>> _read(
    String sql,
    Map<String, Object?> parameters,
  ) async {
    final result = await _connection.query(sql, parameters: parameters);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <MonthPodiumPlace>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? seasonId = row['season_id'];
      final Object? userId = row['user_id'];
      final int? place = _int(row['place']);
      if (seasonId is! String || userId is! String || place == null) {
        return Result.err(_corrupt());
      }
      final Object? photoAt = row['photo_updated_at'];
      final Object? avatarAt = row['avatar_updated_at'];
      out.add(
        MonthPodiumPlace(
          seasonId: SeasonId(seasonId),
          place: place,
          userId: UserId(userId),
          displayName: (row['display_name'] as String?) ?? '',
          points: _int(row['points']) ?? 0,
          exactCount: _int(row['exact_count']) ?? 0,
          decidedCount: _int(row['decided_count']) ?? 0,
          photoUpdatedAt: photoAt is DateTime ? photoAt.toUtc() : null,
          avatarUpdatedAt: avatarAt is DateTime ? avatarAt.toUtc() : null,
        ),
      );
    }
    return Result.ok(List<MonthPodiumPlace>.unmodifiable(out));
  }

  /// The 0191 refusals: one invariant code for the admin.
  static AppError _refusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final name = cause.constraintName ?? '';
    if (name.startsWith('month_podium_')) {
      return const AppError.invariant(
        'champion.podium_refused',
        'رُفض تثبيت المنصة: حدّث الصفحة وأعد المحاولة',
      );
    }
    return error;
  }

  static AppError _corrupt() => const AppError.transient(
    'champion.row_corrupt',
    'a month_podium row could not be read',
  );

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final BigInt v => v.toInt(),
    _ => null,
  };
}
