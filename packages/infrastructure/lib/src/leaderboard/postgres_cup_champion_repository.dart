import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [CupChampionRepository] (migrations 0190 and 0204).
///
/// The titles are read from `gamification.h2h_cup_titles` (written by the
/// Elite Cup's scheduler, append-only) and the pictures live in
/// `gamification.h2h_cup_title_photos`. The database refuses a picture for
/// anyone but the champion of the title: the statements here only add the
/// `WHERE`.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresCupChampionRepository implements CupChampionRepository {
  /// Creates the repository over [_connection].
  const PostgresCupChampionRepository(this._connection);

  final PostgresConnection _connection;

  static const String _listSql = '''
SELECT t.month_start::text AS month_start,
       t.place,
       t.how,
       t.champion::text AS champion_id,
       uc.display_name AS champion_name,
       uc.avatar_updated_at AS champion_avatar_updated_at,
       p.photo_updated_at
FROM gamification.h2h_cup_titles t
LEFT JOIN identity.users uc ON uc.id = t.champion
LEFT JOIN gamification.h2h_cup_title_photos p
  ON p.month_start = t.month_start AND p.place = t.place
ORDER BY t.month_start DESC, t.place
LIMIT @limit::int
''';

  static const String _setPhotoSql = '''
INSERT INTO gamification.h2h_cup_title_photos
  (month_start, place, user_id, photo_bytes, photo_mime, photo_updated_at)
SELECT t.month_start, t.place, t.champion, @bytes, @mime, @now::timestamptz
FROM gamification.h2h_cup_titles t
WHERE t.month_start = @month_start::date
  AND t.place = @place::smallint
  AND t.champion IS NOT NULL
ON CONFLICT (month_start, place) DO UPDATE
SET photo_bytes = EXCLUDED.photo_bytes,
    photo_mime = EXCLUDED.photo_mime,
    photo_updated_at = EXCLUDED.photo_updated_at
RETURNING user_id::text AS user_id
''';

  static const String _removePhotoSql = '''
DELETE FROM gamification.h2h_cup_title_photos
WHERE month_start = @month_start::date AND place = @place::smallint
RETURNING user_id::text AS user_id
''';

  static const String _photoSql = '''
SELECT photo_bytes, photo_mime, photo_updated_at
FROM gamification.h2h_cup_title_photos
WHERE month_start = @month_start::date AND place = @place::smallint
''';

  static AppError _corrupt(String what) => AppError.transient(
    'cup.row_corrupt',
    'an h2h_cup_titles row carries an unreadable $what',
  );

  @override
  Future<Result<List<CupChampion>>> list({required int limit}) async {
    final result = await _connection.query(
      _listSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <CupChampion>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? championId = row['champion_id'];
      if (championId == null) {
        // A vacant title has no champion to show.
        continue;
      }
      final Object? monthStart = row['month_start'];
      final Object? place = row['place'];
      final Object? how = row['how'];
      if (championId is! String ||
          monthStart is! String ||
          place is! num ||
          how is! String) {
        return Result.err(_corrupt('title'));
      }
      final Object? photoAt = row['photo_updated_at'];
      final Object? avatarAt = row['champion_avatar_updated_at'];
      out.add(
        CupChampion(
          monthStart: monthStart,
          place: place.toInt(),
          how: how,
          userId: UserId(championId),
          displayName: (row['champion_name'] as String?) ?? '',
          photoUpdatedAt: photoAt is DateTime ? photoAt.toUtc() : null,
          avatarUpdatedAt: avatarAt is DateTime ? avatarAt.toUtc() : null,
        ),
      );
    }
    return Result.ok(List<CupChampion>.unmodifiable(out));
  }

  @override
  Future<Result<bool>> setPhoto({
    required String monthStart,
    required int place,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _setPhotoSql,
      parameters: {
        'month_start': monthStart,
        'place': place,
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
  Future<Result<bool>> removePhoto({
    required String monthStart,
    required int place,
  }) async {
    final result = await _connection.query(
      _removePhotoSql,
      parameters: {'month_start': monthStart, 'place': place},
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
    required String monthStart,
    required int place,
  }) async {
    final result = await _connection.query(
      _photoSql,
      parameters: {'month_start': monthStart, 'place': place},
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
}
