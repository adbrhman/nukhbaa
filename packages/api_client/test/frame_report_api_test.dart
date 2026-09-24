import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('POST /me/frame-report sends the session counts', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'recorded': true}),
      token: 'jwt-abc',
    );

    final result = await AuthApi(ctx.transport).reportFrames(
      const FrameReportDto(
        build: 'abc1234',
        platform: 'android',
        refreshRateHz: 120,
        frames: 1000,
        slowFrames: 30,
        frozenFrames: 1,
        worstFrameMs: 900,
      ),
    );

    expect((result as Ok<FrameReportAckDto>).value.recorded, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/me/frame-report');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['slow_frames'], 30);
    expect(body['refresh_rate_hz'], 120);
  });

  test('GET /admin/frame-stats reads the totals, days as a query', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'window_days': 14,
        'overall': {
          'build': null,
          'reports': 4,
          'users': 3,
          'frames': 8000,
          'slow_frames': 200,
          'frozen_frames': 3,
          'worst_frame_ms': 1500,
          'last_reported_at': '2026-09-24T09:00:00.000Z',
        },
        'builds': <Object?>[],
      }),
      token: 'jwt-abc',
    );

    final result = await AdminApi(ctx.transport).frameStats(days: 14);

    final stats = (result as Ok<AdminFrameStatsDto>).value;
    expect(stats.windowDays, 14);
    expect(stats.overall.slowPercent, 2.5);
    expect(ctx.captured.single.url.path, '/admin/frame-stats');
    expect(ctx.captured.single.url.queryParameters['days'], '14');
  });
}
