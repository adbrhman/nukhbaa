import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/screen-views/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 6, 12);
}

final class _MemoryViews implements ScreenViewRepository {
  final List<Map<String, int>> reports = [];
  final List<DateTime> days = [];

  @override
  Future<Result<void>> add({
    required UserId userId,
    required DateTime day,
    required Map<String, int> opens,
    required DateTime reportedAt,
  }) async {
    reports.add(opens);
    days.add(day);
    return const Result.ok(null);
  }
}

Future<Response> _call(
  _MemoryViews views,
  HttpMethod method, {
  Object? body,
  AuthenticatedUser? principal,
}) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      recordScreenViews: RecordScreenViews(
        views: views,
        clock: const _FixedClock(),
      ),
    ),
    principal: principal ?? nonMemberPrincipal(),
    method: method,
    body: body,
  ),
);

void main() {
  group('POST /me/screen-views', () {
    test('keeps the known screens of the report', () async {
      final views = _MemoryViews();

      final response = await _call(
        views,
        HttpMethod.post,
        body: {
          'opens': {'duels': 2, 'badges': 1, 'not_a_screen': 4},
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['recorded'], 2);
      expect(views.reports.single, {'duels': 2, 'badges': 1});
      expect(views.days.single, DateTime.utc(2026, 10, 6));
    });

    test('a body without a map of integers is 400 and keeps nothing', () async {
      final views = _MemoryViews();

      final missing = await _call(
        views,
        HttpMethod.post,
        body: <String, Object?>{},
      );
      final notInts = await _call(
        views,
        HttpMethod.post,
        body: {
          'opens': {'duels': 'two'},
        },
      );
      final notAMap = await _call(
        views,
        HttpMethod.post,
        body: {
          'opens': ['duels'],
        },
      );

      expect(missing.statusCode, HttpStatus.badRequest);
      expect(notInts.statusCode, HttpStatus.badRequest);
      expect(notAMap.statusCode, HttpStatus.badRequest);
      expect(views.reports, isEmpty);
    });

    test('a count below one is 400', () async {
      final views = _MemoryViews();

      final response = await _call(
        views,
        HttpMethod.post,
        body: {
          'opens': {'home': 0},
        },
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(views.reports, isEmpty);
    });

    test('the 31st report from one player within an hour is refused', () async {
      final views = _MemoryViews();
      const player = AuthenticatedUser(
        userId: UserId('00000000-0000-4000-8000-0000000000d3'),
        role: PlatformRole.user,
      );
      Future<Response> send() => _call(
        views,
        HttpMethod.post,
        principal: player,
        body: {
          'opens': {'home': 1},
        },
      );

      for (var i = 0; i < 30; i++) {
        expect((await send()).statusCode, HttpStatus.ok);
      }
      final refused = await send();

      expect(refused.statusCode, HttpStatus.tooManyRequests);
      expect(views.reports, hasLength(30));
    });
  });

  test('any other method is 405', () async {
    final response = await _call(_MemoryViews(), HttpMethod.get);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
