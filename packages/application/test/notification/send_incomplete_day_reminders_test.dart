import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

UserId _user(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;

IncompleteDayTarget _target(
  String user, {
  int remaining = 3,
  bool optedIn = true,
  int? utcOffsetMinutes,
  List<String> tokens = const ['t1'],
}) => IncompleteDayTarget(
  userId: _user(user),
  tokens: tokens,
  remaining: remaining,
  optedIn: optedIn,
  utcOffsetMinutes: utcOffsetMinutes,
);

final class _FakeReminders implements IncompleteDayReminderRepository {
  _FakeReminders(this.due, {this.failMark = false});

  final List<IncompleteDayTarget> due;
  final bool failMark;
  final List<String> marked = [];
  final List<String> forgotten = [];
  String? today;
  DateTime? now;
  DateTime? from;
  DateTime? to;

  @override
  Future<Result<List<IncompleteDayTarget>>> dueTargets({
    required String today,
    required DateTime now,
    required DateTime from,
    required DateTime to,
  }) async {
    this.today = today;
    this.now = now;
    this.from = from;
    this.to = to;
    return Result.ok(due);
  }

  @override
  Future<Result<void>> markSent({
    required UserId userId,
    required String sendDate,
    required DateTime now,
  }) async {
    if (failMark) {
      return const Result.err(AppError.transient('test.down', 'down'));
    }
    marked.add('${userId.value}@$sendDate');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async {
    forgotten.addAll(tokens);
    return const Result.ok(null);
  }
}

final class _FakeSender implements PushSender {
  _FakeSender({this.dead = const <String>[]});

  final List<String> dead;
  final List<String> bodies = [];
  final List<String?> links = [];
  final List<List<String>> tokens = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    bodies.add(body);
    links.add(link);
    this.tokens.add(tokens);
    return Result.ok(dead);
  }
}

void main() {
  // Tuesday 2026-09-15 12:00 UTC, 15:00 in Riyadh.
  final now = DateTime.utc(2026, 9, 15, 12);

  group('SendIncompleteDayReminders', () {
    test('tells a player how many matches are still open', () async {
      final reminders = _FakeReminders([
        _target(_userA, tokens: const ['t1', 't2']),
      ]);
      final sender = _FakeSender();

      final result = await SendIncompleteDayReminders(
        reminders: reminders,
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 1);
      expect(reminders.today, '2026-09-15');
      expect(reminders.now, now);
      expect(reminders.from, now.add(const Duration(minutes: 75)));
      expect(reminders.to, now.add(const Duration(minutes: 105)));
      expect(sender.tokens.single, ['t1', 't2']);
      expect(sender.bodies.single, SendIncompleteDayReminders.bodyFor(3));
      expect(sender.links.single, PushLink.fixtures);
      expect(reminders.marked, ['$_userA@2026-09-15']);
    });

    test('a player who switched the reminder off is skipped', () async {
      final reminders = _FakeReminders([
        _target(_userA, optedIn: false),
        _target(_userB),
      ]);
      final sender = _FakeSender();

      final result = await SendIncompleteDayReminders(
        reminders: reminders,
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 1);
      expect(reminders.marked, ['$_userB@2026-09-15']);
    });

    test('a player in their quiet hours is skipped, not recorded', () async {
      // 12:00 UTC is 23:00 at UTC+11.
      final reminders = _FakeReminders([
        _target(_userA, utcOffsetMinutes: 11 * 60),
      ]);
      final sender = _FakeSender();

      final result = await SendIncompleteDayReminders(
        reminders: reminders,
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 0);
      expect(sender.bodies, isEmpty);
      expect(reminders.marked, isEmpty);
    });

    test('nothing open, nothing sent', () async {
      final reminders = _FakeReminders([_target(_userA, remaining: 0)]);
      final sender = _FakeSender();

      final result = await SendIncompleteDayReminders(
        reminders: reminders,
        sender: sender,
      )(now: now);

      expect((result as Ok<int>).value, 0);
      expect(sender.bodies, isEmpty);
    });

    test('dead tokens are retired after the sweep', () async {
      final reminders = _FakeReminders([_target(_userA)]);

      await SendIncompleteDayReminders(
        reminders: reminders,
        sender: _FakeSender(dead: const ['t1']),
      )(now: now);

      expect(reminders.forgotten, ['t1']);
    });

    test('a failed record stops the sweep with the error', () async {
      final reminders = _FakeReminders([_target(_userA)], failMark: true);

      final result = await SendIncompleteDayReminders(
        reminders: reminders,
        sender: _FakeSender(),
      )(now: now);

      expect(result, isA<Err<int>>());
    });
  });

  group('SendIncompleteDayReminders.bodyFor', () {
    test('names one, two, a few and many matches as Arabic counts them', () {
      expect(
        SendIncompleteDayReminders.bodyFor(1),
        contains('مباراة واحدة لم تتوقعها'),
      );
      expect(
        SendIncompleteDayReminders.bodyFor(2),
        contains('مباراتان لم تتوقعهما'),
      );
      expect(
        SendIncompleteDayReminders.bodyFor(5),
        contains('5 مباريات لم تتوقعها'),
      );
      expect(
        SendIncompleteDayReminders.bodyFor(11),
        contains('11 مباراة لم تتوقعها'),
      );
    });
  });
}
