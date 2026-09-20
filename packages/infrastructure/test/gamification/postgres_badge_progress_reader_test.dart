import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_badge_progress_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = '11111111-1111-1111-1111-111111111111';
const _userB = '22222222-2222-2222-2222-222222222222';

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

/// Hermetic unit tests for [PostgresBadgeProgressReader]: a fake
/// [PostgresConnection] replays scripted rows and records every SQL and
/// parameter set. What only a real server can prove (that the filtered
/// counts add up over real events) is checked by hand against the live
/// database, read-only.
void main() {
  group('PostgresBadgeProgressReader.readAll', () {
    test('maps each row to a tally and the badges already held', () async {
      final connection = _rows([
        {
          'user_id': _userA,
          'predictions_placed': 30,
          'perfect_days': '2',
          'weeks_finished': 1,
          'promotions': 1,
          'weeks_won': 0,
          'elite_weeks': 0,
          'unlocked_codes': 'first_prediction,predictions_25',
        },
        {
          'user_id': _userB,
          'predictions_placed': 0,
          'perfect_days': 0,
          'weeks_finished': 0,
          'promotions': 0,
          'weeks_won': 0,
          'elite_weeks': 0,
          'unlocked_codes': null,
        },
      ]);

      final result = await PostgresBadgeProgressReader(connection).readAll();

      final standings = (result as Ok<List<UserBadgeStanding>>).value;
      expect(standings.length, 2);
      expect(standings[0].userId.value, _userA);
      expect(standings[0].progress.predictionsPlaced, 30);
      expect(standings[0].progress.perfectDays, 2);
      expect(standings[0].progress.weeksFinished, 1);
      expect(standings[0].progress.promotions, 1);
      expect(standings[0].progress.weeksWon, 0);
      expect(standings[0].progress.eliteWeeks, 0);
      expect(standings[0].unlocked, <BadgeCode>{
        BadgeCode.firstPrediction,
        BadgeCode.predictions25,
      });
      expect(standings[1].userId.value, _userB);
      expect(standings[1].unlocked, isEmpty);
    });

    test('skips a held code the catalog no longer knows', () async {
      final result = await PostgresBadgeProgressReader(
        _rows([
          {
            'user_id': _userA,
            'predictions_placed': 1,
            'perfect_days': 0,
            'weeks_finished': 0,
            'promotions': 0,
            'weeks_won': 0,
            'elite_weeks': 0,
            'unlocked_codes': 'retired_badge, first_prediction,',
          },
        ]),
      ).readAll();

      final standing = (result as Ok<List<UserBadgeStanding>>).value.single;
      expect(standing.unlocked, <BadgeCode>{BadgeCode.firstPrediction});
    });

    test('an unreadable count reads as zero, never as a badge', () async {
      final result = await PostgresBadgeProgressReader(
        _rows([
          {
            'user_id': _userA,
            'predictions_placed': 'many',
            'perfect_days': null,
            'weeks_finished': 0,
            'promotions': 0,
            'weeks_won': 0,
            'elite_weeks': 0,
            'unlocked_codes': null,
          },
        ]),
      ).readAll();

      final standing = (result as Ok<List<UserBadgeStanding>>).value.single;
      expect(standing.progress.predictionsPlaced, 0);
      expect(standing.progress.perfectDays, 0);
    });

    test('reads an empty list when no player has an event', () async {
      final result = await PostgresBadgeProgressReader(
        _rows(const <Map<String, dynamic>>[]),
      ).readAll();

      expect((result as Ok<List<UserBadgeStanding>>).value, isEmpty);
    });

    test('maps a malformed user id to an error', () async {
      final result = await PostgresBadgeProgressReader(
        _rows([
          {'user_id': 'not-a-uuid'},
        ]),
      ).readAll();

      expect(
        (result as Err<List<UserBadgeStanding>>).error.code,
        'identity.user_id_malformed',
      );
    });

    test('passes a query failure through', () async {
      final result = await PostgresBadgeProgressReader(_fails()).readAll();

      expect(
        (result as Err<List<UserBadgeStanding>>).error.code,
        'db.query_failed',
      );
    });

    test('is one read-only statement over the event stream', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await PostgresBadgeProgressReader(connection).readAll();

      final sql = connection.sqls.single;
      expect(sql, contains('gamification.events'));
      expect(sql, isNot(contains('INSERT')));
      expect(sql, isNot(contains('UPDATE')));
      expect(sql, isNot(contains('DELETE')));
      expect(connection.parameters.single, isEmpty);
    });

    test('the literals in the SQL are the domain wire values', () async {
      // The statement writes each event type, the outcome and the top tier
      // as literals; a wire value renamed in the domain must fail here
      // rather than make a badge unearnable in production.
      final connection = _rows(const <Map<String, dynamic>>[]);

      await PostgresBadgeProgressReader(connection).readAll();

      final sql = connection.sqls.single;
      for (final type in <GamificationEventType>[
        GamificationEventType.predictionPlaced,
        GamificationEventType.dailyChallengeCompleted,
        GamificationEventType.weeklyLeagueFinished,
        GamificationEventType.badgeUnlocked,
      ]) {
        expect(sql, contains("'${type.wireName}'"));
      }
      expect(sql, contains("'${WeeklyLeagueOutcome.promoted.wireName}'"));
      expect(sql, contains("= '${WeeklyLeagueTier.elite.level}'"));
    });
  });
}
