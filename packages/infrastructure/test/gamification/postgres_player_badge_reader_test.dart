import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_player_badge_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-1111-1111-1111-111111111111';

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

Map<String, dynamic> _counts({
  Object? predictions = 0,
  Object? perfectDays = 0,
  Object? weeks = 0,
  Object? promotions = 0,
  Object? won = 0,
  Object? elite = 0,
}) => {
  'predictions_placed': predictions,
  'perfect_days': perfectDays,
  'weeks_finished': weeks,
  'promotions': promotions,
  'weeks_won': won,
  'elite_weeks': elite,
};

const _failure = Result<List<Map<String, dynamic>>>.err(
  AppError.transient('db.query_failed', 'Database query failed'),
);

/// Hermetic unit tests for [PostgresPlayerBadgeReader]: a fake
/// [PostgresConnection] replays scripted rows and records every SQL and
/// parameter set. What only a real server can prove (that the counts add up
/// over real events) is checked by hand against the live database,
/// read-only.
void main() {
  group('PostgresPlayerBadgeReader.recordOf', () {
    test('maps the counts and the held badges with their moments', () async {
      final granted = DateTime.utc(2026, 9, 20, 8);
      final connection = _FakeConnection([
        Result.ok([_counts(predictions: 30, perfectDays: '2', weeks: 1)]),
        Result.ok([
          {'code': 'first_prediction', 'unlocked_at': granted},
          {'code': 'predictions_25', 'unlocked_at': '2026-09-21T09:00:00Z'},
        ]),
      ]);

      final result = await PostgresPlayerBadgeReader(
        connection,
      ).recordOf(const UserId(_user));

      final record = (result as Ok<PlayerBadgeRecord>).value;
      expect(record.progress.predictionsPlaced, 30);
      expect(record.progress.perfectDays, 2);
      expect(record.progress.weeksFinished, 1);
      expect(record.unlockedAt, <BadgeCode, DateTime>{
        BadgeCode.firstPrediction: granted,
        BadgeCode.predictions25: DateTime.utc(2026, 9, 21, 9),
      });
      expect(connection.sqls, hasLength(2));
      expect(connection.parameters, everyElement({'user_id': _user}));
      expect(connection.sqls.first, contains('WHERE e.user_id = @user_id'));
      expect(connection.sqls.last, contains("e.event_type = 'badge_unlocked'"));
    });

    test('the literals match the domain event types', () async {
      final connection = _FakeConnection([
        Result.ok([_counts()]),
        const Result.ok([]),
      ]);

      await PostgresPlayerBadgeReader(connection).recordOf(const UserId(_user));

      final sql = connection.sqls.first;
      expect(
        sql,
        contains("'${GamificationEventType.predictionPlaced.wireName}'"),
      );
      expect(
        sql,
        contains("'${GamificationEventType.dailyChallengeCompleted.wireName}'"),
      );
      expect(
        sql,
        contains("'${GamificationEventType.weeklyLeagueFinished.wireName}'"),
      );
      expect(
        connection.sqls.last,
        contains("'${GamificationEventType.badgeUnlocked.wireName}'"),
      );
    });

    test('a player with no events reads as nothing held', () async {
      final result = await PostgresPlayerBadgeReader(
        _FakeConnection([
          Result.ok([_counts()]),
          const Result.ok([]),
        ]),
      ).recordOf(const UserId(_user));

      final record = (result as Ok<PlayerBadgeRecord>).value;
      expect(record.progress.predictionsPlaced, 0);
      expect(record.unlockedAt, isEmpty);
    });

    test('skips a code the catalog no longer knows', () async {
      final result = await PostgresPlayerBadgeReader(
        _FakeConnection([
          Result.ok([_counts(predictions: 1)]),
          Result.ok([
            {'code': 'retired_badge', 'unlocked_at': DateTime.utc(2026)},
            {'code': ' first_prediction ', 'unlocked_at': DateTime.utc(2026)},
          ]),
        ]),
      ).recordOf(const UserId(_user));

      final record = (result as Ok<PlayerBadgeRecord>).value;
      expect(record.unlockedAt.keys, [BadgeCode.firstPrediction]);
    });

    test('an unreadable count reads as zero and an unreadable moment keeps '
        'the badge held', () async {
      final result = await PostgresPlayerBadgeReader(
        _FakeConnection([
          Result.ok([_counts(predictions: 'many', perfectDays: null)]),
          Result.ok([
            {'code': 'first_prediction', 'unlocked_at': 'yesterday'},
          ]),
        ]),
      ).recordOf(const UserId(_user));

      final record = (result as Ok<PlayerBadgeRecord>).value;
      expect(record.progress.predictionsPlaced, 0);
      expect(record.progress.perfectDays, 0);
      expect(
        record.unlockedAt[BadgeCode.firstPrediction],
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('a failed read is returned, not thrown', () async {
      final result = await PostgresPlayerBadgeReader(
        _FakeConnection([_failure]),
      ).recordOf(const UserId(_user));

      expect((result as Err<PlayerBadgeRecord>).error.code, 'db.query_failed');
    });

    test('a failed second read is returned too', () async {
      final result = await PostgresPlayerBadgeReader(
        _FakeConnection([
          Result.ok([_counts()]),
          _failure,
        ]),
      ).recordOf(const UserId(_user));

      expect(result, isA<Err<PlayerBadgeRecord>>());
    });
  });
}
