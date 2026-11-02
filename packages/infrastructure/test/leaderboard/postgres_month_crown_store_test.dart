import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_month_crown_store.dart';
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

const _season = SeasonId('c2040000-0000-4000-8000-000000000011');

/// Hermetic tests of the row mapping and the parameters. The SQL itself is
/// run against a Postgres 16 with every migration through 0199 applied
/// (`supabase/tests/0199_month_auto_crown_test.sql`).
void main() {
  test('the months due, with their crowning time when crowned', () async {
    final connection = _FakeConnection({
      'month_crown_due': Result.ok([
        {
          'season_id': _season.value,
          'label': '11/2026',
          'end_at': DateTime.utc(2026, 11, 30, 21),
          'crowned_at': null,
        },
        {
          'season_id': 'c2040000-0000-4000-8000-000000000010',
          'label': '10/2026',
          'end_at': DateTime.utc(2026, 10, 31, 21),
          'crowned_at': DateTime.utc(2026, 11, 1, 2),
        },
      ]),
    });

    final result = await PostgresMonthCrownStore(connection).dueMonths(
      now: DateTime.utc(2026, 12, 1),
      window: const Duration(days: 3),
    );

    final months = (result as Ok<List<CrownDueMonth>>).value;
    expect(months.first.seasonId, _season);
    expect(months.first.label, '11/2026');
    expect(months.first.crownedAt, isNull);
    expect(months.last.crownedAt, DateTime.utc(2026, 11, 1, 2));
    expect(connection.params.single['window_hours'], 72);
    expect(connection.params.single['now'], DateTime.utc(2026, 12, 1));
  });

  test(
    'a month\'s state, its counts read whatever their integer type',
    () async {
      final connection = _FakeConnection({
        'month_crown_state': Result.ok([
          {
            'waiting': 1,
            'waiting_names': 'A × B',
            'skipped': BigInt.two,
            'skipped_names': 'C × D، E × F',
            'last_result_at': DateTime.utc(2026, 11, 30, 23),
            'rescore': 0,
          },
        ]),
      });

      final result = await PostgresMonthCrownStore(connection).stateOf(
        season: _season,
        now: DateTime.utc(2026, 12, 1),
        postponedAfter: const Duration(hours: 6),
      );

      final state = (result as Ok<MonthCrownState>).value;
      expect(state.waiting, 1);
      expect(state.waitingNames, 'A × B');
      expect(state.skipped, 2);
      expect(state.skippedNames, 'C × D، E × F');
      expect(state.lastResultAt, DateTime.utc(2026, 11, 30, 23));
      expect(state.rescore, 0);
      expect(connection.params.single['postponed_hours'], 6);
      expect(connection.params.single['season_id'], _season.value);
    },
  );

  test('an unreadable state is a corrupt row', () async {
    final connection = _FakeConnection({
      'month_crown_state': const Result.ok([
        {'waiting': 'x', 'skipped': 0, 'rescore': 0},
      ]),
    });
    final result = await PostgresMonthCrownStore(connection).stateOf(
      season: _season,
      now: DateTime.utc(2026, 12, 1),
      postponedAfter: const Duration(hours: 6),
    );
    expect((result as Err<MonthCrownState>).error.code, 'champion.row_corrupt');
  });

  test('the fixtures to score again, and the prize', () async {
    final connection = _FakeConnection({
      'month_crown_rescore': const Result.ok([
        {'fixture_id': 'c2040000-0000-4000-8000-0000000000f1'},
      ]),
      'month_prize_for': const Result.ok([
        {'prize': '150 ريال سعودي'},
      ]),
    });
    final store = PostgresMonthCrownStore(connection);

    final ids = await store.toRescore(_season);
    expect((ids as Ok<List<FixtureRef>>).value, const [
      FixtureRef('c2040000-0000-4000-8000-0000000000f1'),
    ]);
    final prize = await store.prizeFor(_season);
    expect((prize as Ok<String?>).value, '150 ريال سعودي');
  });

  test('no prize reads as none', () async {
    final connection = _FakeConnection({
      'month_prize_for': const Result.ok([
        {'prize': null},
      ]),
    });
    final prize = await PostgresMonthCrownStore(connection).prizeFor(_season);
    expect((prize as Ok<String?>).value, isNull);
  });

  test('a notice is new when a row comes back', () async {
    final first = _FakeConnection({
      'month_crown_notices': const Result.ok([
        {'kind': 'tie'},
      ]),
    });
    final again = _FakeConnection({});

    final told = await PostgresMonthCrownStore(
      first,
    ).noteOnce(season: _season, kind: 'tie', signature: 'u1,u2');
    final repeated = await PostgresMonthCrownStore(
      again,
    ).noteOnce(season: _season, kind: 'tie', signature: 'u1,u2');

    expect((told as Ok<bool>).value, isTrue);
    expect((repeated as Ok<bool>).value, isFalse);
    expect(first.params.single, {
      'season_id': _season.value,
      'kind': 'tie',
      'signature': 'u1,u2',
    });
  });

  test('the prize set ahead is sent trimmed as given', () async {
    final connection = _FakeConnection({});
    final result = await PostgresMonthCrownStore(connection).setPrize(
      season: _season,
      prize: '200 ريال',
      setBy: const UserId('00000000-0000-4000-8204-0000000000aa'),
      setAt: DateTime.utc(2026, 11, 20, 12),
    );
    expect(result, isA<Ok<void>>());
    expect(connection.sqls.single, contains('competition.month_prizes'));
    expect(connection.params.single, {
      'season_id': _season.value,
      'prize': '200 ريال',
      'set_by': '00000000-0000-4000-8204-0000000000aa',
      'set_at': DateTime.utc(2026, 11, 20, 12),
    });
  });

  test('the latest result written after the crowning', () async {
    final some = _FakeConnection({
      'month_results_after': Result.ok([
        {'written_at': DateTime.utc(2026, 12, 1, 1)},
      ]),
    });
    final none = _FakeConnection({
      'month_results_after': const Result.ok([
        {'written_at': null},
      ]),
    });

    final written = await PostgresMonthCrownStore(
      some,
    ).resultsWrittenAfter(season: _season, since: DateTime.utc(2026, 12, 1));
    final nothing = await PostgresMonthCrownStore(
      none,
    ).resultsWrittenAfter(season: _season, since: DateTime.utc(2026, 12, 1));

    expect((written as Ok<DateTime?>).value, DateTime.utc(2026, 12, 1, 1));
    expect((nothing as Ok<DateTime?>).value, isNull);
    expect(some.params.single['since'], DateTime.utc(2026, 12, 1));
  });
}
