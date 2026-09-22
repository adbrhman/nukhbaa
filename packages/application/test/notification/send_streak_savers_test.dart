import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';
const _fixture = '11111111-1111-4111-8111-111111111111';

UserId _user(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;

StreakSaverTarget _target(String user, {bool optedIn = true}) =>
    StreakSaverTarget(
      userId: _user(user),
      fixtureId: (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value,
      tokens: const ['t1'],
      optedIn: optedIn,
    );

final class _FakeSavers implements StreakSaverRepository {
  _FakeSavers(this.due);

  final List<StreakSaverTarget> due;
  final List<String> marked = [];
  String? today;

  @override
  Future<Result<List<StreakSaverTarget>>> dueTargets({
    required String today,
    required DateTime from,
    required DateTime to,
  }) async {
    this.today = today;
    return Result.ok(due);
  }

  @override
  Future<Result<void>> markSent({
    required StreakSaverTarget target,
    required String sendDate,
    required DateTime now,
  }) async {
    marked.add(target.userId.value);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async =>
      const Result.ok(null);
}

/// A calendar per user: today open, then the completed days before it.
final class _FakeStreaks implements StreakRepository {
  _FakeStreaks(this.runs);

  final Map<String, int> runs;

  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) async {
    final int run = runs[userId.value] ?? 0;
    return Result.ok(<MatchDayCompletion>[
      MatchDayCompletion(day: upToDay, completed: false),
      for (var i = 1; i <= run; i++)
        MatchDayCompletion(
          day: upToDay.subtract(Duration(days: i)),
          completed: true,
        ),
      MatchDayCompletion(
        day: upToDay.subtract(Duration(days: run + 1)),
        completed: false,
      ),
    ]);
  }
}

final class _FakeBudget implements PushBudgetReader {
  _FakeBudget([this.counts = const {}]);

  final Map<String, int> counts;

  @override
  Future<Result<Map<String, int>>> sentCountsSince({
    required List<UserId> userIds,
    required String fromDate,
  }) async => Result.ok(counts);
}

final class _FakeSender implements PushSender {
  final List<String> bodies = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    bodies.add(body);
    return const Result.ok(<String>[]);
  }
}

void main() {
  // Tuesday 2026-09-15 12:00 UTC, 15:00 in Riyadh.
  final now = DateTime.utc(2026, 9, 15, 12);

  group('SendStreakSavers', () {
    test('warns a player carrying a run, with its length', () async {
      final savers = _FakeSavers([_target(_userA)]);
      final sender = _FakeSender();

      final result = await SendStreakSavers(
        savers: savers,
        streaks: _FakeStreaks({_userA: 4}),
        budget: _FakeBudget(),
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 1);
      expect(savers.today, '2026-09-15');
      expect(savers.marked, [_userA]);
      expect(sender.bodies.single, SendStreakSavers.bodyFor(4));
    });

    test('a run shorter than two is not worth a warning', () async {
      final savers = _FakeSavers([_target(_userA), _target(_userB)]);

      final result = await SendStreakSavers(
        savers: savers,
        streaks: _FakeStreaks({_userA: 1, _userB: 0}),
        budget: _FakeBudget(),
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 0);
      expect(savers.marked, isEmpty);
    });

    test('a switched-off player is not warned', () async {
      final savers = _FakeSavers([_target(_userA, optedIn: false)]);

      final result = await SendStreakSavers(
        savers: savers,
        streaks: _FakeStreaks({_userA: 5}),
        budget: _FakeBudget(),
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 0);
    });

    test('a spent budget stops the warning', () async {
      final result = await SendStreakSavers(
        savers: _FakeSavers([_target(_userA)]),
        streaks: _FakeStreaks({_userA: 5}),
        budget: _FakeBudget({_userA: NotificationGate.weeklyBudget}),
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 0);
    });
  });
}
