import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/social/postgres_duel_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// The joins themselves were run against Postgres with migration 0090
// applied. These tests pin the bindings and the row mapping this reader
// owns, including the LEFT JOINs that may find no prediction or score.

const _user = '11111111-1111-4111-8111-111111111111';
const _rival = '22222222-2222-4222-8222-222222222222';
const _season = '33333333-3333-4333-8333-333333333333';
const _fixture = '44444444-4444-4444-8444-444444444444';
const _challenge = '55555555-5555-4555-8555-555555555555';
const _duel = '66666666-6666-4666-8666-666666666666';

final DateTime _kickoff = DateTime.utc(2026, 10, 5, 18);
final DateTime _now = DateTime.utc(2026, 10, 5, 12);

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
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

Map<String, dynamic> _challengeRow({Object? target, Object status = 'open'}) =>
    {
      'id': _challenge,
      'code': 'ABCDEFGHJKMN',
      'season_id': _season,
      'fixture_id': _fixture,
      'home_team': 'Home',
      'away_team': 'Away',
      'kickoff_at': _kickoff,
      'challenger_user_id': _rival,
      'challenger_name': 'Rival',
      'target_user_id': target,
      'capacity': 5,
      'accepted_count': 2,
      'status': status,
      'created_at': _now,
    };

Map<String, dynamic> _duelRow({bool scored = true}) => {
  'id': _duel,
  'challenge_id': _challenge,
  'fixture_id': _fixture,
  'home_team': 'Home',
  'away_team': 'Away',
  'kickoff_at': _kickoff,
  'accepted_at': _now,
  'caller_is_challenger': true,
  'opponent_user_id': _rival,
  'opponent_name': 'Rival',
  'my_home_goals': 2,
  'my_away_goals': 1,
  'my_is_double': true,
  'their_home_goals': null,
  'their_away_goals': null,
  'their_is_double': null,
  'my_grade': scored ? 'exact_scoreline' : null,
  'my_points': scored ? 6 : null,
  'their_grade': scored ? 'pending' : null,
  'their_points': scored ? 0 : null,
};

void main() {
  test('findChallengeByCode binds the code and maps the row', () async {
    final conn = _FakeConnection(Result.ok([_challengeRow()]));
    final code = (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value;
    final result = await PostgresDuelReader(conn).findChallengeByCode(code);

    final preview = (result as Ok<DuelChallengePreview?>).value!;
    expect(preview.challengeId, const DuelChallengeId(_challenge));
    expect(preview.code, code);
    expect(preview.seasonId, const SeasonId(_season));
    expect(preview.homeTeam, 'Home');
    expect(preview.kickoffAt, _kickoff);
    expect(preview.challengerUserId, const UserId(_rival));
    expect(preview.challengerName, 'Rival');
    expect(preview.targetUserId, isNull);
    expect(preview.capacity, 5);
    expect(preview.acceptedCount, 2);
    expect(preview.status, DuelChallengeStatus.open);
    expect(conn.sqls.single, contains('WHERE c.code = @code::text'));
    expect(conn.parameters.single, {'code': 'ABCDEFGHJKMN'});
  });

  test('findChallengeByCode answers null for an unknown code', () async {
    final conn = _FakeConnection(const Result.ok([]));
    final code = (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value;
    final result = await PostgresDuelReader(conn).findChallengeByCode(code);
    expect((result as Ok<DuelChallengePreview?>).value, isNull);
  });

  test('listOpenChallengesFor binds the caller, now and limit', () async {
    final conn = _FakeConnection(Result.ok([_challengeRow(target: _user)]));
    final result = await PostgresDuelReader(
      conn,
    ).listOpenChallengesFor(userId: const UserId(_user), now: _now, limit: 50);

    final list = (result as Ok<List<DuelChallengePreview>>).value;
    expect(list.single.targetUserId, const UserId(_user));
    expect(conn.sqls.single, contains("c.status = 'open'"));
    expect(conn.parameters.single, {
      'user_id': _user,
      'now': _now,
      'limit': 50,
    });
  });

  test('an unknown stored status is a corrupt row', () async {
    final conn = _FakeConnection(
      Result.ok([_challengeRow(status: 'accepted')]),
    );
    final result = await PostgresDuelReader(
      conn,
    ).listOpenChallengesFor(userId: const UserId(_user), now: _now, limit: 50);
    expect(
      (result as Err<List<DuelChallengePreview>>).error.code,
      'social.row_corrupt',
    );
  });

  test('listDuelsFor maps both sides, a missing pick stays null', () async {
    final conn = _FakeConnection(Result.ok([_duelRow()]));
    final result = await PostgresDuelReader(
      conn,
    ).listDuelsFor(userId: const UserId(_user), since: _now, limit: 100);

    final duel = (result as Ok<List<DuelRecord>>).value.single;
    expect(duel.duelId, const DuelId(_duel));
    expect(duel.callerIsChallenger, isTrue);
    expect(duel.opponentUserId, const UserId(_rival));
    expect(duel.myPick!.homeGoals, 2);
    expect(duel.myPick!.isDouble, isTrue);
    expect(duel.opponentPick, isNull);
    expect(duel.myScore!.points, 6);
    expect(duel.myScore!.isFinal, isTrue);
    expect(duel.opponentScore!.isFinal, isFalse);
    expect(conn.sqls.single, contains('LEFT JOIN scoring.fixture_scores'));
    expect(conn.parameters.single, {
      'user_id': _user,
      'since': _now,
      'limit': 100,
    });
  });

  test('listDuelsFor without score rows leaves both scores null', () async {
    final conn = _FakeConnection(Result.ok([_duelRow(scored: false)]));
    final result = await PostgresDuelReader(
      conn,
    ).listDuelsFor(userId: const UserId(_user), since: _now, limit: 100);

    final duel = (result as Ok<List<DuelRecord>>).value.single;
    expect(duel.myScore, isNull);
    expect(duel.opponentScore, isNull);
  });

  test('a transient failure passes through', () async {
    final conn = _FakeConnection(
      const Result.err(
        AppError.transient('db.query_failed', 'Database query failed'),
      ),
    );
    final result = await PostgresDuelReader(
      conn,
    ).listDuelsFor(userId: const UserId(_user), since: _now, limit: 100);
    expect((result as Err<List<DuelRecord>>).error.code, 'db.query_failed');
  });
}
