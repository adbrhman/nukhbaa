import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

UserId _id(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;

final class _FakeReminders implements PredictionReminderRepository {
  _FakeReminders({this.kickoff, this.targets = const []});

  DateTime? kickoff;
  List<ReminderTarget> targets;

  final List<String> markedUsers = [];
  final List<String> forgotten = [];
  String? markedDate;
  int pendingCalls = 0;

  @override
  Future<Result<DateTime?>> firstKickoffInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => Result.ok(kickoff);

  @override
  Future<Result<List<ReminderTarget>>> pendingTargets({
    required DateTime windowStart,
    required DateTime windowEnd,
    required String reminderDate,
  }) async {
    pendingCalls += 1;
    return Result.ok(targets);
  }

  @override
  Future<Result<void>> markSent({
    required List<UserId> userIds,
    required String reminderDate,
    required DateTime now,
  }) async {
    markedDate = reminderDate;
    markedUsers.addAll(userIds.map((u) => u.value));
    return const Result<void>.ok(null);
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async {
    forgotten.addAll(tokens);
    return const Result<void>.ok(null);
  }
}

final class _FakeSender implements PushSender {
  _FakeSender({this.dead = const []});

  List<String> dead;
  final List<String> sentTo = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  }) async {
    sentTo.addAll(tokens);
    return Result.ok(dead);
  }
}

void main() {
  group('SendPredictionReminders', () {
    // 2026-09-15 18:00 UTC+3 => 15:00 UTC.
    final kickoff = DateTime.utc(2026, 9, 15, 15);

    test('sends exactly three hours before the first kickoff', () async {
      final reminders = _FakeReminders(
        kickoff: kickoff,
        targets: [
          ReminderTarget(userId: _id(_userA), tokens: const ['t1', 't2']),
          ReminderTarget(userId: _id(_userB), tokens: const ['t3']),
        ],
      );
      final sender = _FakeSender();
      final useCase = SendPredictionReminders(
        reminders: reminders,
        sender: sender,
      );

      final result = await useCase(now: DateTime.utc(2026, 9, 15, 12));

      expect((result as Ok<int>).value, 2);
      expect(sender.sentTo, ['t1', 't2', 't3']);
      expect(reminders.markedUsers, [_userA, _userB]);
      expect(reminders.markedDate, '2026-09-15');
    });

    test('does nothing outside the firing window', () async {
      final reminders = _FakeReminders(kickoff: kickoff);
      final sender = _FakeSender();
      final useCase = SendPredictionReminders(
        reminders: reminders,
        sender: sender,
      );

      // Six hours ahead: too early.
      final early = await useCase(now: DateTime.utc(2026, 9, 15, 9));
      // Half an hour ahead: too late.
      final late = await useCase(now: DateTime.utc(2026, 9, 15, 14, 30));

      expect((early as Ok<int>).value, 0);
      expect((late as Ok<int>).value, 0);
      expect(reminders.pendingCalls, 0);
      expect(sender.sentTo, isEmpty);
    });

    test('does nothing on a day with no fixtures', () async {
      final reminders = _FakeReminders();
      final sender = _FakeSender();
      final useCase = SendPredictionReminders(
        reminders: reminders,
        sender: sender,
      );

      final result = await useCase(now: DateTime.utc(2026, 9, 15, 12));

      expect((result as Ok<int>).value, 0);
      expect(sender.sentTo, isEmpty);
    });

    test('everyone predicted -> nothing sent, nothing marked', () async {
      final reminders = _FakeReminders(kickoff: kickoff);
      final sender = _FakeSender();
      final useCase = SendPredictionReminders(
        reminders: reminders,
        sender: sender,
      );

      final result = await useCase(now: DateTime.utc(2026, 9, 15, 12));

      expect((result as Ok<int>).value, 0);
      expect(reminders.pendingCalls, 1);
      expect(reminders.markedUsers, isEmpty);
    });

    test('retires the tokens the sender reported dead', () async {
      final reminders = _FakeReminders(
        kickoff: kickoff,
        targets: [
          ReminderTarget(userId: _id(_userA), tokens: const ['t1', 't2']),
        ],
      );
      final sender = _FakeSender(dead: ['t2']);
      final useCase = SendPredictionReminders(
        reminders: reminders,
        sender: sender,
      );

      await useCase(now: DateTime.utc(2026, 9, 15, 12));

      expect(reminders.forgotten, ['t2']);
      expect(reminders.markedUsers, [_userA]);
    });
  });
}
