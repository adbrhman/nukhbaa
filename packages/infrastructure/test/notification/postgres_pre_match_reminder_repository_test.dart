import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_pre_match_reminder_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _fixture = '11111111-1111-4111-8111-111111111111';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _response;
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

Map<String, dynamic> _row(String token, {Object? preMatch = true}) => {
  'user_id': _userA,
  'fixture_id': _fixture,
  'home_team': 'home',
  'away_team': 'away',
  'token': token,
  'utc_offset_minutes': 180,
  'pre_match': preMatch,
};

/// Hermetic unit tests for the row mapping of
/// [PostgresPreMatchReminderRepository]. Which followers are due is SQL,
/// checked by hand against the live database.
void main() {
  group('dueTargets', () {
    test('folds devices into one target per (user, fixture)', () async {
      final connection = _FakeConnection(Result.ok([_row('t1'), _row('t2')]));
      final from = DateTime.utc(2026, 9, 15, 13, 30);
      final to = DateTime.utc(2026, 9, 15, 14);

      final result = await PostgresPreMatchReminderRepository(
        connection,
      ).dueTargets(from: from, to: to);

      final targets = (result as Ok<List<PreMatchTarget>>).value;
      expect(targets, hasLength(1));
      expect(targets.single.tokens, ['t1', 't2']);
      expect(targets.single.fixtureId.value, _fixture);
      expect(targets.single.optedIn, isTrue);
      expect(targets.single.utcOffsetMinutes, 180);
      expect(connection.params.single, {'from': from, 'to': to});
      expect(connection.sqls.single, contains('identity.user_favorite_teams'));
    });

    test('a non-boolean switch is transient, not a guess', () async {
      final connection = _FakeConnection(
        Result.ok([_row('t1', preMatch: 'true')]),
      );

      final result = await PostgresPreMatchReminderRepository(
        connection,
      ).dueTargets(from: DateTime.utc(2026), to: DateTime.utc(2026));

      expect(
        (result as Err<List<PreMatchTarget>>).error.kind,
        ErrorKind.transient,
      );
    });
  });

  group('markSent', () {
    test('records the fixture against the user and the Riyadh day', () async {
      final connection = _FakeConnection(const Result.ok([]));
      final target = PreMatchTarget(
        userId: (UserId.tryParse(_userA) as Ok<UserId>).value,
        fixtureId: (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value,
        homeTeam: 'home',
        awayTeam: 'away',
        tokens: const ['t1'],
        optedIn: true,
      );

      final result = await PostgresPreMatchReminderRepository(connection)
          .markSent(
            target: target,
            sendDate: '2026-09-15',
            now: DateTime.utc(2026, 9, 15, 12),
          );

      expect(result.isOk, isTrue);
      expect(connection.params.single['fixture_id'], _fixture);
      expect(connection.params.single['send_date'], '2026-09-15');
      expect(connection.sqls.single, contains('proactive_sends'));
    });
  });
}
