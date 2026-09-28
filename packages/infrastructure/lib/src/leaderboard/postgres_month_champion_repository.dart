import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [MonthChampionRepository] (migration 0077).
///
/// The fixtures of a month are read exactly as the live board reads them
/// (`competition.season_fixtures`), and a fixture counts as unscored while
/// `scoring.fixture_results` holds no result for it. A crowning is one
/// transaction: every champion of the month or none.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresMonthChampionRepository implements MonthChampionRepository {
  /// Creates the repository over [_connection].
  const PostgresMonthChampionRepository(this._connection);

  final PostgresConnection _connection;

  static const String _monthSql = '''
SELECT s.id::text AS season_id,
       s.label,
       s.start_at,
       s.end_at,
       (SELECT count(*)
          FROM competition.season_fixtures sf
          LEFT JOIN scoring.fixture_results r ON r.fixture_id = sf.fixture_id
         WHERE sf.season_id = s.id
           AND r.fixture_id IS NULL)::bigint AS unscored
FROM competition.seasons s
WHERE s.id = @season_id::uuid
''';

  static const String _fixturesSql = '''
SELECT fixture_id::text AS fixture_id
FROM competition.season_fixtures
WHERE season_id = @season_id::uuid
ORDER BY display_order, fixture_id
''';

  static const String _crownedSql = '''
SELECT user_id::text AS user_id
FROM competition.month_champions
WHERE season_id = @season_id::uuid
ORDER BY user_id
''';

  static const String _crownSql = '''
INSERT INTO competition.month_champions
  (season_id, user_id, points, exact_count, decided_count, referral_points,
   crowned_at, crowned_by)
VALUES
  (@season_id::uuid, @user_id::uuid, @points::int, @exact_count::int,
   @decided_count::int, @referral_points::int, @crowned_at::timestamptz,
   @crowned_by::uuid)
''';

  static const String _listSql = '''
SELECT c.season_id::text AS season_id,
       s.label AS season_label,
       c.user_id::text AS user_id,
       u.display_name,
       c.points,
       c.exact_count,
       c.decided_count,
       c.referral_points,
       c.crowned_at,
       c.photo_updated_at,
       u.avatar_updated_at
FROM competition.month_champions c
JOIN competition.seasons s ON s.id = c.season_id
JOIN identity.users u ON u.id = c.user_id
ORDER BY c.crowned_at DESC, c.points DESC, c.user_id
LIMIT @limit::int
''';

  static const String _setPhotoSql = '''
UPDATE competition.month_champions
SET photo_bytes = @bytes,
    photo_mime = @mime,
    photo_updated_at = @now::timestamptz
WHERE season_id = @season_id::uuid
  AND user_id = @user_id::uuid
RETURNING user_id::text AS user_id
''';

  static const String _photoSql = '''
SELECT photo_bytes, photo_mime, photo_updated_at
FROM competition.month_champions
WHERE season_id = @season_id::uuid
  AND user_id = @user_id::uuid
''';

  static AppError _corrupt(String what) => AppError.transient(
    'champion.row_corrupt',
    'a month_champions row carries an unreadable $what',
  );

  @override
  Future<Result<ChampionMonth?>> month(SeasonId season) async {
    final params = {'season_id': season.value};
    final monthRows = await _connection.query(_monthSql, parameters: params);
    if (monthRows is Err<List<Map<String, dynamic>>>) {
      return Result.err(monthRows.error);
    }
    final rows = (monthRows as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final row = rows.first;
    final Object? label = row['label'];
    final Object? startAt = row['start_at'];
    final Object? endAt = row['end_at'];
    if (label is! String || startAt is! DateTime || endAt is! DateTime) {
      return Result.err(_corrupt('season'));
    }

    final fixtureRows = await _connection.query(
      _fixturesSql,
      parameters: params,
    );
    if (fixtureRows is Err<List<Map<String, dynamic>>>) {
      return Result.err(fixtureRows.error);
    }
    final fixtures = <FixtureRef>[];
    for (final fixture
        in (fixtureRows as Ok<List<Map<String, dynamic>>>).value) {
      final Object? id = fixture['fixture_id'];
      if (id is! String) {
        return Result.err(_corrupt('fixture'));
      }
      fixtures.add(FixtureRef(id));
    }

    final crownedRows = await _connection.query(
      _crownedSql,
      parameters: params,
    );
    if (crownedRows is Err<List<Map<String, dynamic>>>) {
      return Result.err(crownedRows.error);
    }
    final crowned = <UserId>[];
    for (final champion
        in (crownedRows as Ok<List<Map<String, dynamic>>>).value) {
      final Object? id = champion['user_id'];
      if (id is! String) {
        return Result.err(_corrupt('champion'));
      }
      crowned.add(UserId(id));
    }

    return Result.ok(
      ChampionMonth(
        seasonId: season,
        label: label,
        startAt: startAt.toUtc(),
        endAt: endAt.toUtc(),
        fixtures: List<FixtureRef>.unmodifiable(fixtures),
        unscoredFixtures: _int(row['unscored']),
        crowned: List<UserId>.unmodifiable(crowned),
      ),
    );
  }

  @override
  Future<Result<void>> crown({
    required SeasonId season,
    required List<ChampionToCrown> champions,
    required UserId crownedBy,
    required DateTime crownedAt,
  }) {
    return _connection.runInTransaction<void>((tx) async {
      for (final champion in champions) {
        final inserted = await tx.query(
          _crownSql,
          parameters: {
            'season_id': season.value,
            'user_id': champion.userId.value,
            'points': champion.points,
            'exact_count': champion.exactCount,
            'decided_count': champion.decidedCount,
            'referral_points': champion.referralPoints,
            'crowned_at': crownedAt.toUtc(),
            'crowned_by': crownedBy.value,
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
  Future<Result<List<MonthChampion>>> list({required int limit}) async {
    final result = await _connection.query(
      _listSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <MonthChampion>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? seasonId = row['season_id'];
      final Object? label = row['season_label'];
      final Object? userId = row['user_id'];
      final Object? crownedAt = row['crowned_at'];
      if (seasonId is! String ||
          label is! String ||
          userId is! String ||
          crownedAt is! DateTime) {
        return Result.err(_corrupt('champion'));
      }
      final Object? photoAt = row['photo_updated_at'];
      final Object? avatarAt = row['avatar_updated_at'];
      out.add(
        MonthChampion(
          seasonId: SeasonId(seasonId),
          seasonLabel: label,
          userId: UserId(userId),
          displayName: (row['display_name'] as String?) ?? '',
          points: _int(row['points']),
          exactCount: _int(row['exact_count']),
          decidedCount: _int(row['decided_count']),
          referralPoints: _int(row['referral_points']),
          crownedAt: crownedAt.toUtc(),
          photoUpdatedAt: photoAt is DateTime ? photoAt.toUtc() : null,
          avatarUpdatedAt: avatarAt is DateTime ? avatarAt.toUtc() : null,
        ),
      );
    }
    return Result.ok(List<MonthChampion>.unmodifiable(out));
  }

  @override
  Future<Result<bool>> setPhoto({
    required SeasonId season,
    required UserId user,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _setPhotoSql,
      parameters: {
        'season_id': season.value,
        'user_id': user.value,
        // Uint8List, never a bare List<int>: see PostgresUserDirectory -- a
        // List<int> is sent as an integer ARRAY and lands as its text form.
        'bytes': Uint8List.fromList(bytes),
        'mime': mime,
        'now': now.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  }) async {
    final result = await _connection.query(
      _photoSql,
      parameters: {'season_id': season.value, 'user_id': user.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final Object? bytes = rows.first['photo_bytes'];
    final Object? mime = rows.first['photo_mime'];
    final Object? updatedAt = rows.first['photo_updated_at'];
    if (bytes == null || mime == null || updatedAt == null) {
      return const Result.ok(null);
    }
    if (bytes is! List<int> || mime is! String || updatedAt is! DateTime) {
      return Result.err(_corrupt('picture'));
    }
    return Result.ok(
      StoredAvatar(bytes: bytes, mime: mime, updatedAt: updatedAt.toUtc()),
    );
  }

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final BigInt v => v.toInt(),
    _ => 0,
  };
}
