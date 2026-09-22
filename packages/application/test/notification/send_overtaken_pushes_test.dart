import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _league = '99999999-0000-4000-8000-000000000009';
const _a = UserId('aaaaaaaa-0000-0000-0000-000000000001');
const _b = UserId('bbbbbbbb-0000-0000-0000-000000000002');

WeeklyLeagueId _leagueId() =>
    (WeeklyLeagueId.tryParse(_league) as Ok<WeeklyLeagueId>).value;

WeeklyLeagueEntry _entry(UserId user, int points) => WeeklyLeagueEntry(
  userId: user,
  points: points,
  exactCount: 0,
  decidedCount: 0,
  joinedAt: DateTime.utc(2026, 9, 14),
);

final class _FakeOvertaken implements OvertakenRepository {
  _FakeOvertaken({this.marks = const {}, this.alreadySent = false});

  Map<UserId, int> marks;
  final bool alreadySent;
  final List<UserId> told = [];
  DateTime? weekStart;

  @override
  Future<Result<List<WeeklyLeagueId>>> openLeagues({
    required DateTime weekStart,
  }) async {
    this.weekStart = weekStart;
    return Result.ok([_leagueId()]);
  }

  @override
  Future<Result<Map<UserId, int>>> rankMarks(WeeklyLeagueId leagueId) async =>
      Result.ok(marks);

  @override
  Future<Result<void>> saveRankMarks({
    required WeeklyLeagueId leagueId,
    required Map<UserId, int> ranks,
    required DateTime now,
  }) async {
    marks = ranks;
    return const Result.ok(null);
  }

  @override
  Future<Result<Map<UserId, OvertakenRecipient>>> recipients({
    required WeeklyLeagueId leagueId,
    required List<UserId> userIds,
  }) async => Result.ok({
    for (final user in userIds)
      user: OvertakenRecipient(
        tokens: const ['t1'],
        optedIn: true,
        alreadySent: alreadySent,
      ),
  });

  @override
  Future<Result<void>> markSent({
    required UserId userId,
    required WeeklyLeagueId leagueId,
    required String sendDate,
    required DateTime now,
  }) async {
    told.add(userId);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async =>
      const Result.ok(null);
}

final class _FakeStandings implements WeeklyLeagueStandingsReader {
  _FakeStandings(this.entries);

  final List<WeeklyLeagueEntry> entries;

  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) async => Result.ok(entries);
}

final class _FakeProfiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final user in userIds)
      user: WeeklyLeagueMemberProfile(displayName: 'name-${user.value[0]}'),
  });
}

final class _FakeBudget implements PushBudgetReader {
  @override
  Future<Result<Map<String, int>>> sentCountsSince({
    required List<UserId> userIds,
    required String fromDate,
  }) async => const Result.ok({});
}

final class _FakeSender implements PushSender {
  final List<String> bodies = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  }) async {
    bodies.add(body);
    return const Result.ok(<String>[]);
  }
}

void main() {
  // Tuesday 2026-09-15 12:00 UTC: the week opened on Monday the 14th.
  final now = DateTime.utc(2026, 9, 15, 12);

  SendOvertakenPushes build(
    _FakeOvertaken overtaken,
    List<WeeklyLeagueEntry> entries,
    _FakeSender sender,
  ) => SendOvertakenPushes(
    overtaken: overtaken,
    standings: _FakeStandings(entries),
    profiles: _FakeProfiles(),
    budget: _FakeBudget(),
    sender: sender,
  );

  group('SendOvertakenPushes', () {
    test('tells the member who was passed, and by whom', () async {
      final overtaken = _FakeOvertaken(marks: {_a: 1, _b: 2});
      final sender = _FakeSender();

      final result = await build(overtaken, [
        _entry(_a, 3),
        _entry(_b, 9),
      ], sender)(now: now);

      expect((result as Ok<int>).value, 1);
      expect(overtaken.told, [_a]);
      expect(sender.bodies.single, SendOvertakenPushes.bodyFor('name-b', 2));
      expect(overtaken.marks, {_b: 1, _a: 2});
      expect(overtaken.weekStart, DateTime.utc(2026, 9, 14));
    });

    test('the first look only sets the marks', () async {
      final overtaken = _FakeOvertaken();
      final sender = _FakeSender();

      final result = await build(overtaken, [
        _entry(_a, 3),
        _entry(_b, 9),
      ], sender)(now: now);

      expect((result as Ok<int>).value, 0);
      expect(sender.bodies, isEmpty);
      expect(overtaken.marks, {_b: 1, _a: 2});
    });

    test('a member already told in this group is not told again', () async {
      final overtaken = _FakeOvertaken(
        marks: {_a: 1, _b: 2},
        alreadySent: true,
      );
      final sender = _FakeSender();

      final result = await build(overtaken, [
        _entry(_a, 3),
        _entry(_b, 9),
      ], sender)(now: now);

      expect((result as Ok<int>).value, 0);
      expect(sender.bodies, isEmpty);
    });
  });
}
