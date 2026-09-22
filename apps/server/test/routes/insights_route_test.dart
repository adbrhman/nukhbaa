import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/insights/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _Reader implements PredictionOutcomeReader {
  _Reader({this.failWith});

  final AppError? failWith;

  @override
  Future<Result<List<PredictionOutcome>>> outcomesOf({
    required UserId userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
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
        leagueName: 'L1',
      ),
    ]);
  }

  @override
  Future<Result<AccuracyTally>> communityTally({
    required DateTime from,
    required DateTime to,
  }) async => const Result.ok(AccuracyTally(decided: 4, correct: 2, exact: 0));
}

Future<Response> _call(_Reader reader, HttpMethod method) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      getMyInsights: GetMyInsights(
        outcomes: reader,
        clock: _FixedClock(DateTime.utc(2026, 9, 23, 12)),
      ),
    ),
    principal: nonMemberPrincipal(),
    method: method,
  ),
);

void main() {
  group('GET /me/insights', () {
    test('answers the insights, recap and community percent', () async {
      final response = await _call(_Reader(), HttpMethod.get);

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['community_percent'], 50);
      expect((body['month'] as Map<String, Object?>)['exact'], 1);
      final lastWeek = body['last_week'] as Map<String, Object?>;
      expect(lastWeek['week_start'], '2026-09-14');
      expect((lastWeek['best'] as Map<String, Object?>)['exact'], true);
      expect(body['weeks'], hasLength(8));
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await _call(
        _Reader(failWith: const AppError.transient('db.down', 'down')),
        HttpMethod.get,
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });
  });

  test('any other method is 405', () async {
    final response = await _call(_Reader(), HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
