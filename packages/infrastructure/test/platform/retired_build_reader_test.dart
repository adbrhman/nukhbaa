import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/cached_retired_build_reader.dart';
import 'package:infrastructure/src/platform/postgres_retired_build_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const String _p1 = '00000000-0149-4000-8149-000000000001';

/// Answers every query with [rows], recording what was asked. The SQL is
/// exercised by `supabase/tests/retired_build_players_query_test.sql`.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this.rows);

  Result<List<Map<String, dynamic>>> rows;
  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    return rows;
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

/// Counts reads; fails while [failing].
final class _Inner implements RetiredBuildReader {
  Set<UserId> players = <UserId>{const UserId(_p1)};
  bool failing = false;
  int reads = 0;

  @override
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before) async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    return failing
        ? const Result.err(AppError.transient('db.down', 'down'))
        : Result.ok(players);
  }
}

void main() {
  final before = DateTime.utc(2026, 10, 9, 21);

  group('PostgresRetiredBuildReader', () {
    test('reads the players for the cutoff, as UTC', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'user_id': _p1},
        ]),
      );

      final result = await PostgresRetiredBuildReader(
        connection,
      ).playersOnBuildsBefore(before);

      expect((result as Ok<Set<UserId>>).value, {const UserId(_p1)});
      expect(connection.sqls.single, PostgresRetiredBuildReader.playersSql);
      expect(connection.parameters.single, {
        'before': '2026-10-09T21:00:00.000Z',
      });
    });

    test('a row that names no user is an error, never a guess', () async {
      final result = await PostgresRetiredBuildReader(
        _FakeConnection(
          const Result.ok([
            {'user_id': 'not-a-user'},
          ]),
        ),
      ).playersOnBuildsBefore(before);

      expect(
        (result as Err<Set<UserId>>).error.code,
        'platform.frame_report_corrupt',
      );
    });
  });

  group('CachedRetiredBuildReader', () {
    test('one read every ten minutes, shared by concurrent callers', () async {
      var now = DateTime.utc(2026, 10, 26, 12);
      final inner = _Inner();
      final cached = CachedRetiredBuildReader(inner, now: () => now);

      await Future.wait([
        cached.playersOnBuildsBefore(before),
        cached.playersOnBuildsBefore(before),
      ]);
      expect(inner.reads, 1);

      now = now.add(const Duration(minutes: 9));
      await cached.playersOnBuildsBefore(before);
      expect(inner.reads, 1);

      inner.players = const <UserId>{};
      now = now.add(const Duration(minutes: 2));
      final fresh = await cached.playersOnBuildsBefore(before);
      expect((fresh as Ok<Set<UserId>>).value, isEmpty);
      expect(inner.reads, 2);
    });

    test('a failed read is not held', () async {
      final inner = _Inner()..failing = true;
      final cached = CachedRetiredBuildReader(inner);

      expect(
        await cached.playersOnBuildsBefore(before),
        isA<Err<Set<UserId>>>(),
      );
      inner.failing = false;
      expect(
        await cached.playersOnBuildsBefore(before),
        isA<Ok<Set<UserId>>>(),
      );
      expect(inner.reads, 2);
    });
  });
}
