import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/frame-stats/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 24, 12);
}

final class _Reports implements FrameReportRepository {
  _Reports(this.answer);

  final List<FrameTotals> answer;
  DateTime? since;
  List<DeviceTotals> deviceAnswer = const [];

  @override
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  }) async => const Result.ok(null);

  @override
  Future<Result<List<DeviceTotals>>> devices({
    required DateTime since,
    required int minUsers,
    required int limit,
  }) async => Result.ok(deviceAnswer);

  @override
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  }) async {
    this.since = since;
    return Result.ok(answer);
  }
}

FrameTotals _t(String? build, {String? platform}) => FrameTotals(
  build: build,
  platform: platform,
  reports: 4,
  users: 3,
  frames: 8000,
  slowFrames: 200,
  frozenFrames: 3,
  worstFrameMs: 1500,
  lastReportedAt: DateTime.utc(2026, 9, 24, 9),
);

Future<Response> _call(
  _Reports reports,
  AuthenticatedUser principal, {
  HttpMethod method = HttpMethod.get,
  Map<String, String> query = const {},
}) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      adminGetFrameStats: AdminGetFrameStats(
        reports: reports,
        clock: const _FixedClock(),
      ),
    ),
    principal: principal,
    method: method,
    queryParameters: query,
  ),
);

void main() {
  group('GET /admin/frame-stats', () {
    test('an admin reads the totals, overall and per build', () async {
      final reports = _Reports([_t(null), _t('abc1234')])
        ..deviceAnswer = const [
          DeviceTotals(
            deviceModel: 'samsung SM-A105F',
            reports: 9,
            users: 4,
            frames: 9000,
            slowFrames: 1800,
            frozenFrames: 2,
          ),
        ];

      final response = await _call(
        reports,
        adminPrincipal(),
        query: const {'days': '14'},
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['window_days'], 14);
      final overall = body['overall']! as Map<String, Object?>;
      expect(overall['frames'], 8000);
      expect(overall['slow_frames'], 200);
      expect(overall['last_reported_at'], '2026-09-24T09:00:00.000Z');
      final builds = body['builds']! as List<Object?>;
      expect((builds.single! as Map<String, Object?>)['build'], 'abc1234');
      expect(reports.since, DateTime.utc(2026, 9, 10, 12));
      final devices = body['devices']! as List<Object?>;
      final device = devices.single! as Map<String, Object?>;
      expect(device['device_model'], 'samsung SM-A105F');
      expect(device['users'], 4);
    });

    test('a build on two platforms reads as two rows', () async {
      final reports = _Reports([
        _t(null),
        _t('abc1234', platform: 'android'),
        _t('abc1234', platform: 'web'),
      ]);

      final response = await _call(reports, adminPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final builds = (body['builds']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(builds.map((b) => b['platform']), ['android', 'web']);
      expect(
        (body['overall']! as Map<String, Object?>).containsKey('platform'),
        isFalse,
        reason: 'the overall row spans every platform',
      );
    });

    test('a player is refused', () async {
      final response = await _call(_Reports(const []), userPrincipal());

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('any other method is 405', () async {
      final response = await _call(
        _Reports(const []),
        adminPrincipal(),
        method: HttpMethod.post,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
