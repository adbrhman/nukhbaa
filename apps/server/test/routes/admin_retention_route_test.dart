import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/retention/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  // Monday 2026-09-28 in Riyadh.
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 28, 12);
}

final class _Reader implements RetentionReader {
  DateTime? weeksFrom;
  List<WeeklyActivity> weekAnswer = const [];
  List<RetentionCohort> cohortAnswer = const [];

  @override
  Future<Result<List<WeeklyActivity>>> weeks({
    required DateTime from,
    required DateTime through,
  }) async {
    weeksFrom = from;
    return Result.ok(weekAnswer);
  }

  @override
  Future<Result<List<RetentionCohort>>> cohorts({
    required DateTime from,
    required DateTime today,
  }) async => Result.ok(cohortAnswer);
}

Future<Response> _call(
  _Reader reader,
  AuthenticatedUser principal, {
  HttpMethod method = HttpMethod.get,
  Map<String, String> query = const {},
}) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      adminGetRetention: AdminGetRetention(
        reader: reader,
        clock: const _FixedClock(),
      ),
    ),
    principal: principal,
    method: method,
    queryParameters: query,
  ),
);

void main() {
  group('GET /admin/retention', () {
    test('an admin reads every week of the window, newest first', () async {
      final reader = _Reader()
        ..weekAnswer = [
          WeeklyActivity(
            weekStart: DateTime.utc(2026, 9, 14),
            activeUsers: 12,
            active3Plus: 5,
            leagueActive: 7,
            leagueActive3Plus: 4,
            leagueMembers: 9,
            leagueReturned: 6,
          ),
        ]
        ..cohortAnswer = [
          RetentionCohort(
            weekStart: DateTime.utc(2026, 9, 21),
            users: 3,
            day1Eligible: 3,
            day1: 2,
            day7Eligible: 0,
            day7: 0,
            day14Eligible: 0,
            day14: 0,
            week4Eligible: 0,
            week4: 0,
          ),
        ];

      final response = await _call(
        reader,
        adminPrincipal(),
        query: const {'weeks': '3'},
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['today'], '2026-09-28');
      expect(reader.weeksFrom, DateTime.utc(2026, 9, 14));
      final weeks = (body['weeks']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(weeks.map((w) => w['week_start']), [
        '2026-09-28',
        '2026-09-21',
        '2026-09-14',
      ]);
      expect(weeks.first['complete'], isFalse);
      expect(weeks.first['active_users'], 0);
      expect(weeks.last['active_users'], 12);
      expect(
        weeks.last['league_returned'],
        6,
        reason: 'the week after 14/9 has ended',
      );
      expect(weeks[1]['league_returned'], isNull);
      final cohorts = (body['cohorts']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(cohorts[1]['users'], 3);
      expect(cohorts[1]['day1'], {'eligible': 3, 'retained': 2});
    });

    test('a player is refused', () async {
      final response = await _call(_Reader(), userPrincipal());

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('any other method is 405', () async {
      final response = await _call(
        _Reader(),
        adminPrincipal(),
        method: HttpMethod.post,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
