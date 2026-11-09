import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_cup_champion_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Answers each statement by the first [answers] key its SQL contains.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this.answers);

  final Map<String, Result<List<Map<String, dynamic>>>> answers;
  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    for (final entry in answers.entries) {
      if (sql.contains(entry.key)) {
        return entry.value;
      }
    }
    return const Result.ok([]);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

/// Hermetic tests of the row mapping. The SQL itself was run against a
/// Postgres 16 with every migration through 0204 applied
/// (`supabase/tests/0204_cup_champion_photos_test.sql`).
void main() {
  test('the list reads each champion and leaves a vacant title out', () async {
    final connection = _FakeConnection({
      'FROM gamification.h2h_cup_titles': Result.ok([
        {
          'month_start': '2099-11-01',
          'place': 1,
          'how': 'final',
          'champion_id': '00000000-0000-4000-8204-000000000004',
          'champion_name': 'P4',
          'champion_avatar_updated_at': DateTime.utc(2099, 10),
          'photo_updated_at': DateTime.utc(2099, 12),
        },
        {
          'month_start': '2099-11-01',
          'place': 2,
          'how': 'walkover',
          'champion_id': '00000000-0000-4000-8204-000000000005',
          'champion_name': null,
          'champion_avatar_updated_at': null,
          'photo_updated_at': null,
        },
        {
          'month_start': '2099-11-01',
          'place': 3,
          'how': 'vacant',
          'champion_id': null,
          'champion_name': null,
          'champion_avatar_updated_at': null,
          'photo_updated_at': null,
        },
      ]),
    });

    final result = await PostgresCupChampionRepository(
      connection,
    ).list(limit: 30);

    final champions = (result as Ok<List<CupChampion>>).value;
    expect(champions.map((c) => c.place), [1, 2]);
    expect(champions.first.displayName, 'P4');
    expect(champions.first.photoUpdatedAt, DateTime.utc(2099, 12));
    expect(champions.first.avatarUpdatedAt, DateTime.utc(2099, 10));
    expect(champions.last.displayName, '');
    expect(champions.last.photoUpdatedAt, isNull);
    expect(connection.params.single, {'limit': 30});
  });

  test('a row that cannot be read is a transient error', () async {
    final connection = _FakeConnection({
      'FROM gamification.h2h_cup_titles': const Result.ok([
        {'month_start': 7, 'place': 1, 'how': 'final', 'champion_id': 'x'},
      ]),
    });

    final result = await PostgresCupChampionRepository(
      connection,
    ).list(limit: 30);

    expect((result as Err<List<CupChampion>>).error.code, 'cup.row_corrupt');
  });

  test('a picture is set as bytes for a month and a path', () async {
    final connection = _FakeConnection({
      'INSERT INTO gamification.h2h_cup_title_photos': const Result.ok([
        {'user_id': '00000000-0000-4000-8204-000000000004'},
      ]),
    });
    final repo = PostgresCupChampionRepository(connection);

    final stored = await repo.setPhoto(
      monthStart: '2099-11-01',
      place: 1,
      bytes: const [1, 2, 3],
      mime: 'image/png',
      now: DateTime.utc(2099, 12),
    );

    expect((stored as Ok<bool>).value, isTrue);
    expect(connection.params.single['bytes'], isA<Uint8List>());
    expect(connection.params.single['month_start'], '2099-11-01');
    expect(connection.params.single['place'], 1);

    final none = await PostgresCupChampionRepository(_FakeConnection({}))
        .setPhoto(
          monthStart: '2099-11-01',
          place: 3,
          bytes: const [1],
          mime: 'image/png',
          now: DateTime.utc(2099, 12),
        );
    expect((none as Ok<bool>).value, isFalse);
  });

  test('a picture is read back, removed, or absent', () async {
    final photo = _FakeConnection({
      'FROM gamification.h2h_cup_title_photos': Result.ok([
        {
          'photo_bytes': Uint8List.fromList(const [9, 8]),
          'photo_mime': 'image/webp',
          'photo_updated_at': DateTime.utc(2099, 12),
        },
      ]),
    });
    final read = await PostgresCupChampionRepository(
      photo,
    ).photo(monthStart: '2099-11-01', place: 1);
    final avatar = (read as Ok<StoredAvatar?>).value!;
    expect(avatar.bytes, [9, 8]);
    expect(avatar.mime, 'image/webp');

    final absent = await PostgresCupChampionRepository(
      _FakeConnection({}),
    ).photo(monthStart: '2099-11-01', place: 2);
    expect((absent as Ok<StoredAvatar?>).value, isNull);

    final removed = await PostgresCupChampionRepository(
      _FakeConnection({
        'DELETE FROM gamification.h2h_cup_title_photos': const Result.ok([
          {'user_id': '00000000-0000-4000-8204-000000000004'},
        ]),
      }),
    ).removePhoto(monthStart: '2099-11-01', place: 1);
    expect((removed as Ok<bool>).value, isTrue);
  });
}
