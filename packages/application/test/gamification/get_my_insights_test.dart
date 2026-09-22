import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _FakeReader implements PredictionOutcomeReader {
  _FakeReader({this.failure});

  final AppError? failure;
  DateTime? from;
  DateTime? communityFrom;

  @override
  Future<Result<List<PredictionOutcome>>> outcomesOf({
    required UserId userId,
    required DateTime from,
    required DateTime to,
  }) async {
    this.from = from;
    final error = failure;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok([
      PredictionOutcome(
        fixtureId: 'f1',
        kickoffAt: DateTime.utc(2026, 9, 16, 18),
        homeTeam: 'home',
        awayTeam: 'away',
        grade: PredictionGrade.exact,
        points: 3,
        followed: false,
      ),
    ]);
  }

  @override
  Future<Result<AccuracyTally>> communityTally({
    required DateTime from,
    required DateTime to,
  }) async {
    communityFrom = from;
    return const Result.ok(AccuracyTally(decided: 10, correct: 6, exact: 1));
  }
}

AuthenticatedUser _principal() => const AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
  email: 'a@example.com',
  displayName: 'Human',
);

void main() {
  // Wednesday 2026-09-23 12:00 UTC, 15:00 in Riyadh.
  final now = DateTime.utc(2026, 9, 23, 12);

  group('GetMyInsights', () {
    test('reads the window in Riyadh time and computes', () async {
      final reader = _FakeReader();

      final result = await GetMyInsights(
        outcomes: reader,
        clock: _FixedClock(now),
      )(principal: _principal());

      final value = (result as Ok<MyInsights>).value;
      expect(reader.from, DateTime.utc(2026, 8, 2, 21));
      expect(reader.communityFrom, DateTime.utc(2026, 8, 31, 21));
      expect(value.community.percent, 60);
      expect(value.insights.lastWeek!.points, 3);
      expect(value.insights.month.exact, 1);
    });

    test('a read failure surfaces', () async {
      final result = await GetMyInsights(
        outcomes: _FakeReader(
          failure: const AppError.transient('db.down', 'down'),
        ),
        clock: _FixedClock(now),
      )(principal: _principal());

      expect((result as Err<MyInsights>).error.code, 'db.down');
    });
  });
}
