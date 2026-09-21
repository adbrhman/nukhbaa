import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';
const _fixture1 = '11111111-1111-4111-8111-111111111111';
const _fixture2 = '22222222-2222-4222-8222-222222222222';

UserId _user(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;
FixtureRef _fixture(String raw) =>
    (FixtureRef.tryParse(raw) as Ok<FixtureRef>).value;

PreMatchTarget _target(
  String user,
  String fixture, {
  List<String> tokens = const ['t1'],
  bool optedIn = true,
  int? utcOffsetMinutes,
}) => PreMatchTarget(
  userId: _user(user),
  fixtureId: _fixture(fixture),
  homeTeam: 'home',
  awayTeam: 'away',
  tokens: tokens,
  optedIn: optedIn,
  utcOffsetMinutes: utcOffsetMinutes,
);

final class _FakeReminders implements PreMatchReminderRepository {
  _FakeReminders(this.due, {this.markFailure});

  final List<PreMatchTarget> due;
  final AppError? markFailure;
  final List<(DateTime, DateTime)> windows = [];
  final List<String> marked = [];
  final List<String> forgotten = [];
  String? markedDate;

  @override
  Future<Result<List<PreMatchTarget>>> dueTargets({
    required DateTime from,
    required DateTime to,
  }) async {
    windows.add((from, to));
    return Result.ok(due);
  }

  @override
  Future<Result<void>> markSent({
    required PreMatchTarget target,
    required String sendDate,
    required DateTime now,
  }) async {
    final failure = markFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    markedDate = sendDate;
    marked.add('${target.userId.value}/${target.fixtureId.value}');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async {
    forgotten.addAll(tokens);
    return const Result.ok(null);
  }
}

final class _FakeBudget implements PushBudgetReader {
  _FakeBudget([this.counts = const {}]);

  final Map<String, int> counts;
  String? from;

  @override
  Future<Result<Map<String, int>>> sentCountsSince({
    required List<UserId> userIds,
    required String fromDate,
  }) async {
    from = fromDate;
    return Result.ok(counts);
  }
}

final class _FakeSender implements PushSender {
  _FakeSender({this.dead = const {}});

  final Set<String> dead;
  final List<String> bodies = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  }) async {
    bodies.add(body);
    return Result.ok(<String>[
      for (final token in tokens)
        if (dead.contains(token)) token,
    ]);
  }
}

void main() {
  // Tuesday 2026-09-15 12:00 UTC, 15:00 in Riyadh.
  final now = DateTime.utc(2026, 9, 15, 12);

  group('SendPreMatchReminders', () {
    test('pushes each due follower once and records it', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1),
        _target(_userB, _fixture1),
      ]);
      final budget = _FakeBudget();
      final sender = _FakeSender();

      final result = await SendPreMatchReminders(
        reminders: reminders,
        budget: budget,
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 2);
      expect(reminders.marked, ['$_userA/$_fixture1', '$_userB/$_fixture1']);
      expect(reminders.markedDate, '2026-09-15');
      expect(budget.from, '2026-09-14');
      expect(reminders.windows.single, (
        now.add(SendPreMatchReminders.leadMin),
        now.add(SendPreMatchReminders.leadMax),
      ));
      expect(sender.bodies, hasLength(2));
      expect(sender.bodies.first, contains('home'));
    });

    test('a switched-off follower is skipped and not recorded', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1, optedIn: false),
      ]);
      final sender = _FakeSender();

      final result = await SendPreMatchReminders(
        reminders: reminders,
        budget: _FakeBudget(),
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 0);
      expect(sender.bodies, isEmpty);
      expect(reminders.marked, isEmpty);
    });

    test('a follower in their quiet hours is skipped', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1, utcOffsetMinutes: 660),
      ]);

      final result = await SendPreMatchReminders(
        reminders: reminders,
        budget: _FakeBudget(),
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 0);
    });

    test('the budget is shared and counted as the sweep goes', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1),
        _target(_userA, _fixture2),
      ]);

      final result = await SendPreMatchReminders(
        reminders: reminders,
        budget: _FakeBudget({_userA: NotificationGate.weeklyBudget - 1}),
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 1);
      expect(reminders.marked, ['$_userA/$_fixture1']);
    });

    test('dead tokens are forgotten', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1, tokens: const ['t1', 'gone']),
      ]);

      await SendPreMatchReminders(
        reminders: reminders,
        budget: _FakeBudget(),
        sender: _FakeSender(dead: {'gone'}),
      )(now: now);

      expect(reminders.forgotten, ['gone']);
    });

    test('a failed record stops the sweep and surfaces', () async {
      final reminders = _FakeReminders([
        _target(_userA, _fixture1),
        _target(_userB, _fixture1),
      ], markFailure: const AppError.transient('db.down', 'down'));
      final sender = _FakeSender();

      final result = await SendPreMatchReminders(
        reminders: reminders,
        budget: _FakeBudget(),
        sender: sender,
      )(now: now);

      expect((result as Err<int>).error.code, 'db.down');
      expect(sender.bodies, hasLength(1));
    });

    test('nothing due -> the budget is never read', () async {
      final budget = _FakeBudget();

      final result = await SendPreMatchReminders(
        reminders: _FakeReminders(const []),
        budget: budget,
        sender: _FakeSender(),
      )(now: now);

      expect((result as Ok<int>).value, 0);
      expect(budget.from, isNull);
    });
  });
}
