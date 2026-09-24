import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/frame-report/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 24, 12);
}

final class _MemoryReports implements FrameReportRepository {
  final List<FrameReport> kept = [];
  final List<DeviceTotals> deviceAnswer = const [];

  @override
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  }) async {
    kept.add(report);
    return const Result.ok(null);
  }

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
  }) async => const Result.ok([]);
}

Future<Response> _call(
  _MemoryReports reports,
  HttpMethod method, {
  Object? body,
}) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      recordFrameReport: RecordFrameReport(
        reports: reports,
        clock: const _FixedClock(),
      ),
    ),
    principal: userPrincipal(),
    method: method,
    body: body,
  ),
);

Map<String, Object?> _body({int slow = 30}) => {
  'build': 'abc1234',
  'platform': 'android',
  'refresh_rate_hz': 120,
  'frames': 1000,
  'slow_frames': slow,
  'frozen_frames': 1,
  'worst_frame_ms': 900,
  'device_model': 'samsung SM-A105F',
};

void main() {
  group('POST /me/frame-report', () {
    test('keeps a sound report', () async {
      final reports = _MemoryReports();

      final response = await _call(reports, HttpMethod.post, body: _body());

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['recorded'], true);
      expect(reports.kept.single.slowFrames, 30);
      expect(reports.kept.single.refreshRateHz, 120);
      expect(reports.kept.single.deviceModel, 'samsung SM-A105F');
    });

    test('an app from before 0071 sends no model and is still kept', () async {
      final reports = _MemoryReports();

      final response = await _call(
        reports,
        HttpMethod.post,
        body: Map<String, Object?>.of(_body())..remove('device_model'),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(reports.kept.single.deviceModel, isNull);
    });

    test('an impossible or incomplete report is 400, nothing kept', () async {
      final reports = _MemoryReports();

      final impossible = await _call(
        reports,
        HttpMethod.post,
        body: _body(slow: 5000),
      );
      final missing = await _call(
        reports,
        HttpMethod.post,
        body: Map<String, Object?>.of(_body())..remove('frames'),
      );

      expect(impossible.statusCode, HttpStatus.badRequest);
      expect(missing.statusCode, HttpStatus.badRequest);
      expect(reports.kept, isEmpty);
    });

    test('any other method is 405', () async {
      final response = await _call(_MemoryReports(), HttpMethod.get);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
