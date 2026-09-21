import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_weekly_league_profile_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
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

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection([Result.ok(rows)]);

_FakeConnection _fails() => _FakeConnection([
  const Result.err(
    AppError.transient('db.query_failed', 'Database query failed'),
  ),
]);

Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> _read(
  _FakeConnection connection, {
  List<UserId> ids = const [UserId(_userA), UserId(_userB)],
}) => PostgresWeeklyLeagueProfileReader(connection).profilesOf(ids);

void main() {
  group('PostgresWeeklyLeagueProfileReader.profilesOf', () {
    test('maps each row to a name and, when there is one, a picture', () async {
      final connection = _rows([
        {
          'user_id': _userA,
          'display_name': 'Nora',
          'avatar_updated_at': DateTime.utc(2026, 9, 1, 8),
        },
        {
          'user_id': _userB,
          'display_name': '  Sami  ',
          'avatar_updated_at': null,
        },
      ]);

      final result = await _read(connection);

      final profiles =
          (result as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
      expect(profiles, hasLength(2));
      expect(profiles[const UserId(_userA)]?.displayName, 'Nora');
      expect(
        profiles[const UserId(_userA)]?.avatarUpdatedAt,
        DateTime.utc(2026, 9, 1, 8),
      );
      expect(profiles[const UserId(_userB)]?.displayName, 'Sami');
      expect(profiles[const UserId(_userB)]?.avatarUpdatedAt, isNull);
    });

    test('reads a picture version that arrives as text', () async {
      final connection = _rows([
        {
          'user_id': _userA,
          'display_name': 'Nora',
          'avatar_updated_at': '2026-09-01T08:00:00Z',
        },
      ]);

      final result = await _read(connection);

      final profiles =
          (result as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
      expect(
        profiles[const UserId(_userA)]?.avatarUpdatedAt,
        DateTime.utc(2026, 9, 1, 8),
      );
    });

    test('binds the ids as plain strings under one parameter', () async {
      final connection = _rows(const []);

      await _read(connection);

      expect(connection.parameters.single, {
        'ids': [_userA, _userB],
      });
    });

    test('issues one statement and never names the picture bytes', () async {
      final connection = _rows(const []);

      await _read(connection);

      expect(connection.sqls, hasLength(1));
      expect(connection.sqls.single, isNot(contains('avatar_bytes')));
      expect(connection.sqls.single, contains('avatar_updated_at'));
    });

    test('an empty id list issues no statement', () async {
      final connection = _rows(const []);

      final result = await _read(connection, ids: const []);

      expect(
        (result as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value,
        isEmpty,
      );
      expect(connection.sqls, isEmpty);
    });

    test('a row whose user id is malformed is dropped', () async {
      final connection = _rows([
        {'user_id': 'not-a-uuid', 'display_name': 'Ghost'},
        {'user_id': _userA, 'display_name': 'Nora'},
      ]);

      final result = await _read(connection);

      final profiles =
          (result as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
      expect(profiles.keys, [const UserId(_userA)]);
    });

    test('a row with no name is dropped', () async {
      final connection = _rows([
        {'user_id': _userA, 'display_name': '   '},
        {'user_id': _userB, 'display_name': null},
      ]);

      final result = await _read(connection);

      expect(
        (result as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value,
        isEmpty,
      );
    });

    test('a failed query is returned, not swallowed', () async {
      final result = await _read(_fails());

      expect(result, isA<Err<Map<UserId, WeeklyLeagueMemberProfile>>>());
      expect(
        (result as Err<Map<UserId, WeeklyLeagueMemberProfile>>).error.code,
        'db.query_failed',
      );
    });
  });
}
