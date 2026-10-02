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
  DateTime nowUtc() => DateTime.utc(2026, 10, 2, 12);
}

final class _CountingReports implements FrameReportRepository {
  int stored = 0;

  @override
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  }) async {
    stored++;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<DeviceTotals>>> devices({
    required DateTime since,
    required int minUsers,
    required int limit,
  }) async => const Result.ok([]);

  @override
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  }) async => const Result.ok([]);
}

const Map<String, Object?> _report = {
  'build': 'abc1234',
  'platform': 'android',
  'refresh_rate_hz': 60,
  'frames': 1000,
  'slow_frames': 10,
  'frozen_frames': 0,
  'worst_frame_ms': 80,
};

void main() {
  test('the 31st frame report from one player within an hour is refused '
      'and never stored', () async {
    final reports = _CountingReports();
    const player = AuthenticatedUser(
      userId: UserId('00000000-0000-4000-8000-0000000000c1'),
      role: PlatformRole.user,
    );
    Future<Response> send(AuthenticatedUser principal) => route.onRequest(
      wireContext(
        root: CompositionRoot.forTesting(
          recordFrameReport: RecordFrameReport(
            reports: reports,
            clock: const _FixedClock(),
          ),
        ),
        principal: principal,
        body: _report,
      ),
    );

    for (var i = 0; i < 30; i++) {
      expect((await send(player)).statusCode, HttpStatus.ok);
    }
    final refused = await send(player);

    expect(refused.statusCode, HttpStatus.tooManyRequests);
    expect((await decodeBody(refused))['code'], 'request.rate_limited');
    expect(reports.stored, 30);

    // An admin is not counted.
    expect((await send(adminPrincipal())).statusCode, HttpStatus.ok);
    expect(reports.stored, 31);
  });
}
