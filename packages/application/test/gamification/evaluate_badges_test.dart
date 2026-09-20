import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart' show FakeIdGenerator;

final _now = DateTime.utc(2026, 9, 22, 8);

String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

UserBadgeStanding _standing(
  int user, {
  BadgeProgress progress = const BadgeProgress(),
  Set<BadgeCode> unlocked = const <BadgeCode>{},
}) => UserBadgeStanding(
  userId: UserId(_id(user)),
  progress: progress,
  unlocked: unlocked,
);

EvaluateBadges _useCase({
  required _FakeProgress progress,
  required _FakeEvents events,
}) => EvaluateBadges(
  progress: progress,
  events: events,
  idGenerator: FakeIdGenerator(<String>[_id(900)]),
);

List<String> _keys(_FakeEvents events) => <String>[
  for (final event in events.recorded) event.dedupeKey,
];

void main() {
  group('EvaluateBadges', () {
    test('does nothing when nobody has an event yet', () async {
      final events = _FakeEvents();

      final result = await _useCase(
        progress: _FakeProgress(const <UserBadgeStanding>[]),
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 0);
      expect(events.recorded, isEmpty);
    });

    test('awards every badge that is earned and not yet held', () async {
      final events = _FakeEvents();
      final progress = _FakeProgress([
        _standing(
          1,
          progress: const BadgeProgress(predictionsPlaced: 25, perfectDays: 1),
        ),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 3);
      expect(_keys(events), <String>[
        'badge_unlocked:${_id(1)}:first_prediction',
        'badge_unlocked:${_id(1)}:predictions_25',
        'badge_unlocked:${_id(1)}:first_perfect_day',
      ]);
      for (final event in events.recorded) {
        expect(event.type, GamificationEventType.badgeUnlocked);
        expect(event.occurredAt, _now);
      }
    });

    test('a badge already held is not awarded again', () async {
      final events = _FakeEvents();
      final progress = _FakeProgress([
        _standing(
          1,
          progress: const BadgeProgress(predictionsPlaced: 1),
          unlocked: <BadgeCode>{BadgeCode.firstPrediction},
        ),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 0);
      expect(events.recorded, isEmpty);
    });

    test('only the badge still missing is awarded', () async {
      final events = _FakeEvents();
      final progress = _FakeProgress([
        _standing(
          1,
          progress: const BadgeProgress(predictionsPlaced: 25),
          unlocked: <BadgeCode>{BadgeCode.firstPrediction},
        ),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 1);
      expect(_keys(events), <String>[
        'badge_unlocked:${_id(1)}:predictions_25',
      ]);
    });

    test('a badge held stays held when its count is lower now', () async {
      // The stream is append-only: what was earned is never taken back, and
      // the evaluator has no way to write a removal.
      final events = _FakeEvents();
      final progress = _FakeProgress([
        _standing(
          1,
          progress: const BadgeProgress(),
          unlocked: <BadgeCode>{BadgeCode.leagueElite},
        ),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 0);
      expect(events.recorded, isEmpty);
    });

    test('each player is awarded on their own tally', () async {
      final events = _FakeEvents();
      final progress = _FakeProgress([
        _standing(1, progress: const BadgeProgress(predictionsPlaced: 1)),
        _standing(2),
        _standing(3, progress: const BadgeProgress(eliteWeeks: 1)),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 2);
      expect(_keys(events), <String>[
        'badge_unlocked:${_id(1)}:first_prediction',
        'badge_unlocked:${_id(3)}:league_elite',
      ]);
    });

    test('a failed read is passed through and writes nothing', () async {
      final events = _FakeEvents();
      final progress = _FakeProgress(const <UserBadgeStanding>[])
        ..failWith = const AppError.transient('db.down', 'down');

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Err<int>).error.code, 'db.down');
      expect(events.recorded, isEmpty);
    });

    test('one player failing does not stop the others', () async {
      final events = _FakeEvents()
        ..failingUsers = <String>{_id(1)}
        ..failWith = const AppError.transient('db.down', 'down');
      final progress = _FakeProgress([
        _standing(1, progress: const BadgeProgress(predictionsPlaced: 1)),
        _standing(2, progress: const BadgeProgress(predictionsPlaced: 1)),
      ]);

      final result = await _useCase(
        progress: progress,
        events: events,
      ).call(now: _now);

      expect((result as Err<int>).error.code, 'db.down');
      expect(_keys(events), <String>[
        'badge_unlocked:${_id(2)}:first_prediction',
      ]);
    });
  });
}

final class _FakeProgress implements BadgeProgressReader {
  _FakeProgress(this.standings);

  final List<UserBadgeStanding> standings;
  AppError? failWith;

  @override
  Future<Result<List<UserBadgeStanding>>> readAll() async {
    final error = failWith;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(standings);
  }
}

final class _FakeEvents implements GamificationEventSink {
  final List<GamificationEvent> recorded = <GamificationEvent>[];
  Set<String> failingUsers = <String>{};
  AppError? failWith;

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    final error = failWith;
    if (error != null &&
        (failingUsers.isEmpty || failingUsers.contains(event.userId.value))) {
      return Result.err(error);
    }
    recorded.add(event);
    return const Result.ok(null);
  }
}
