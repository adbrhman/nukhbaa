import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_month_champion_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Answers each statement by the first [answers] key its SQL contains.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this.answers);

  final Map<String, Result<List<Map<String, dynamic>>>> answers;
  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];
  int transactions = 0;

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
  ) async {
    transactions++;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

const _season = SeasonId('c7700000-0000-4000-8000-000000000009');

/// Hermetic tests of the row mapping. The SQL itself was run against a
/// Postgres 16 with every migration through 0077 applied.
void main() {
  test(
    'a month carries its window, fixtures, unscored count and crowned',
    () async {
      final connection = _FakeConnection({
        'FROM competition.seasons s': Result.ok([
          {
            'season_id': _season.value,
            'label': '09/2026',
            'start_at': DateTime.utc(2026, 9),
            'end_at': DateTime.utc(2026, 9, 30, 21),
            'unscored': 1,
          },
        ]),
        'FROM competition.season_fixtures': const Result.ok([
          {'fixture_id': 'c7700000-0000-4000-8000-0000000000f1'},
          {'fixture_id': 'c7700000-0000-4000-8000-0000000000f2'},
        ]),
        'FROM competition.month_champions': const Result.ok([
          {'user_id': '00000000-0000-4000-8077-000000000001'},
        ]),
      });

      final result = await PostgresMonthChampionRepository(
        connection,
      ).month(_season);

      final month = (result as Ok<ChampionMonth?>).value!;
      expect(month.label, '09/2026');
      expect(month.endAt, DateTime.utc(2026, 9, 30, 21));
      expect(month.fixtures, hasLength(2));
      expect(month.unscoredFixtures, 1);
      expect(month.crowned, [
        const UserId('00000000-0000-4000-8077-000000000001'),
      ]);
      expect(connection.params.first['season_id'], _season.value);
    },
  );

  test('an unknown month is null', () async {
    final result = await PostgresMonthChampionRepository(
      _FakeConnection({}),
    ).month(_season);

    expect((result as Ok<ChampionMonth?>).value, isNull);
  });

  test('a crowning writes every champion in one transaction', () async {
    final connection = _FakeConnection({});

    final result = await PostgresMonthChampionRepository(connection).crown(
      season: _season,
      champions: const [
        ChampionToCrown(
          userId: UserId('00000000-0000-4000-8077-000000000001'),
          points: 42,
          exactCount: 6,
          decidedCount: 30,
          referralPoints: 2,
        ),
        ChampionToCrown(
          userId: UserId('00000000-0000-4000-8077-000000000002'),
          points: 42,
          exactCount: 6,
          decidedCount: 28,
          referralPoints: 2,
        ),
      ],
      crownedBy: const UserId('00000000-0000-4000-8077-0000000000aa'),
      crownedAt: DateTime.utc(2026, 10, 1, 12),
    );

    expect(result, isA<Ok<void>>());
    expect(connection.transactions, 1);
    expect(connection.sqls, hasLength(2));
    expect(connection.params.first['points'], 42);
    expect(connection.params.last['decided_count'], 28);
    expect(
      connection.params.first['crowned_at'],
      DateTime.utc(2026, 10, 1, 12),
    );
  });

  test('a failed insert fails the crowning', () async {
    final result =
        await PostgresMonthChampionRepository(
          _FakeConnection({
            'INSERT INTO competition.month_champions': const Result.err(
              AppError.transient('db.query_failed', 'Database query failed'),
            ),
          }),
        ).crown(
          season: _season,
          champions: const [
            ChampionToCrown(
              userId: UserId('00000000-0000-4000-8077-000000000001'),
              points: 42,
              exactCount: 6,
              decidedCount: 30,
              referralPoints: 0,
            ),
          ],
          crownedBy: const UserId('00000000-0000-4000-8077-0000000000aa'),
          crownedAt: DateTime.utc(2026, 10, 1, 12),
        );

    expect(result, isA<Err<void>>());
  });

  test('the list maps names, figures and picture times', () async {
    final result = await PostgresMonthChampionRepository(
      _FakeConnection({
        'ORDER BY c.crowned_at DESC': Result.ok([
          {
            'season_id': _season.value,
            'season_label': '09/2026',
            'user_id': '00000000-0000-4000-8077-000000000001',
            'display_name': 'Ahmad',
            'points': 42,
            'exact_count': 6,
            'decided_count': 30,
            'referral_points': 2,
            'crowned_at': DateTime.utc(2026, 10, 1, 12),
            'photo_updated_at': DateTime.utc(2026, 10, 1, 12, 5),
            'avatar_updated_at': null,
          },
        ]),
      }),
    ).list(limit: 48);

    final champion = (result as Ok<List<MonthChampion>>).value.single;
    expect(champion.displayName, 'Ahmad');
    expect(champion.points, 42);
    expect(champion.referralPoints, 2);
    expect(champion.photoUpdatedAt, DateTime.utc(2026, 10, 1, 12, 5));
    expect(champion.avatarUpdatedAt, isNull);
  });

  test('the picture goes in as bytea bytes, and a stranger is false', () async {
    final connection = _FakeConnection({});

    final result = await PostgresMonthChampionRepository(connection).setPhoto(
      season: _season,
      user: const UserId('00000000-0000-4000-8077-000000000003'),
      bytes: const [137, 80, 78, 71],
      mime: 'image/png',
      now: DateTime.utc(2026, 10, 1, 12, 5),
    );

    expect((result as Ok<bool>).value, isFalse);
    expect(connection.params.single['bytes'], isA<Uint8List>());
  });

  test('a picture is read back; none is null', () async {
    final withPhoto =
        await PostgresMonthChampionRepository(
          _FakeConnection({
            'SELECT photo_bytes': Result.ok([
              {
                'photo_bytes': Uint8List.fromList(const [137, 80, 78, 71]),
                'photo_mime': 'image/png',
                'photo_updated_at': DateTime.utc(2026, 10, 1, 12, 5),
              },
            ]),
          }),
        ).photo(
          season: _season,
          user: const UserId('00000000-0000-4000-8077-000000000001'),
        );
    expect((withPhoto as Ok<StoredAvatar?>).value?.mime, 'image/png');

    final without =
        await PostgresMonthChampionRepository(
          _FakeConnection({
            'SELECT photo_bytes': const Result.ok([
              {
                'photo_bytes': null,
                'photo_mime': null,
                'photo_updated_at': null,
              },
            ]),
          }),
        ).photo(
          season: _season,
          user: const UserId('00000000-0000-4000-8077-000000000001'),
        );
    expect((without as Ok<StoredAvatar?>).value, isNull);
  });
}
