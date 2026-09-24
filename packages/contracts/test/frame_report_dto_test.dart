import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('FrameReportDto round-trips through JSON', () {
    const dto = FrameReportDto(
      build: 'abc1234',
      platform: 'android',
      refreshRateHz: 120,
      frames: 1000,
      slowFrames: 30,
      frozenFrames: 1,
      worstFrameMs: 900,
      deviceModel: 'samsung SM-A105F',
    );

    final back = FrameReportDto.fromJson(
      (jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>),
    );

    expect(back.toJson(), dto.toJson());
  });

  test('AdminFrameStatsDto round-trips; shares are per frame', () {
    const totals = FrameTotalsDto(
      build: null,
      reports: 4,
      users: 3,
      frames: 8000,
      slowFrames: 200,
      frozenFrames: 3,
      worstFrameMs: 1500,
      lastReportedAt: '2026-09-24T09:00:00.000Z',
    );
    const dto = AdminFrameStatsDto(
      windowDays: 7,
      overall: totals,
      builds: [totals],
      devices: [
        DeviceTotalsDto(
          deviceModel: 'samsung SM-A105F',
          reports: 9,
          users: 4,
          frames: 9000,
          slowFrames: 1800,
          frozenFrames: 2,
        ),
      ],
    );

    final back = AdminFrameStatsDto.fromJson(
      (jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>),
    );

    expect(back.toJson(), dto.toJson());
    expect(back.overall.slowPercent, 2.5);
    expect(back.overall.frozenPercent, 0.04);
    expect(back.devices.single.slowPercent, 20);
    expect(
      const FrameTotalsDto(
        build: null,
        reports: 0,
        users: 0,
        frames: 0,
        slowFrames: 0,
        frozenFrames: 0,
        worstFrameMs: 0,
        lastReportedAt: null,
      ).slowPercent,
      0,
    );
  });
}
