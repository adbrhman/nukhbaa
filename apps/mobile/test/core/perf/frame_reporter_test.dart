/// [FrameReporter] through its public surface: frames counted against the
/// display's refresh interval, one report per session sent when the app
/// leaves the foreground, nothing sent from a build without a sha or from
/// a session too short to mean anything.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/perf/frame_reporter.dart';

Duration _ms(num ms) => Duration(microseconds: (ms * 1000).round());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FrameReporter reporter(
    List<FrameReportDto> sent, {
    String build = 'abc1234',
    int hz = 120,
  }) => FrameReporter(
    send: (r) async => sent.add(r),
    build: build,
    platform: 'android',
    refreshRateHz: () => hz,
  );

  test('counts slow against 120 Hz and reports on pause', () async {
    final sent = <FrameReportDto>[];
    final r = reporter(sent);
    for (int i = 0; i < 200; i++) {
      r.addFrame(build: _ms(4), raster: _ms(6));
    }
    // 9 ms is fine at 60 Hz but past 8.3 ms at 120 Hz.
    r.addFrame(build: _ms(9), raster: _ms(2));
    r.addFrame(build: _ms(3), raster: _ms(750));

    r.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    final FrameReportDto report = sent.single;
    expect(report.frames, 202);
    expect(report.slowFrames, 2);
    expect(report.frozenFrames, 1);
    expect(report.worstFrameMs, 750);
    expect(report.refreshRateHz, 120);
    expect(report.build, 'abc1234');
    expect(r.frames, 0, reason: 'a new session starts after a report');
  });

  test('the same frame is not slow at 60 Hz', () async {
    final sent = <FrameReportDto>[];
    final r = reporter(sent, hz: 60);
    for (int i = 0; i < 150; i++) {
      r.addFrame(build: _ms(9), raster: _ms(9));
    }

    await r.flush();

    expect(sent.single.slowFrames, 0);
  });

  test('no sha or a short session sends nothing', () async {
    final sent = <FrameReportDto>[];
    final local = reporter(sent, build: '');
    final short = reporter(sent);
    for (int i = 0; i < 500; i++) {
      local.addFrame(build: _ms(4), raster: _ms(4));
    }
    for (int i = 0; i < FrameReporter.minFrames - 1; i++) {
      short.addFrame(build: _ms(4), raster: _ms(4));
    }

    await local.flush();
    await short.flush();

    expect(sent, isEmpty);
  });

  test('the device model read at start rides on the report', () async {
    final sent = <FrameReportDto>[];
    final r = FrameReporter(
      send: (report) async => sent.add(report),
      build: 'abc1234',
      platform: 'android',
      refreshRateHz: () => 60,
      readDeviceModel: () async => 'samsung SM-A105F',
    )..start();
    addTearDown(r.stop);
    await Future<void>.delayed(Duration.zero);
    for (int i = 0; i < 150; i++) {
      r.addFrame(build: _ms(4), raster: _ms(4));
    }

    await r.flush();

    expect(r.deviceModel, 'samsung SM-A105F');
    expect(sent.single.deviceModel, 'samsung SM-A105F');
  });

  test('a model the platform will not give is simply absent', () async {
    final r = FrameReporter(
      send: (_) async {},
      build: 'abc1234',
      platform: 'android',
      refreshRateHz: () => 60,
      readDeviceModel: () async => throw StateError('no plugin'),
    )..start();
    addTearDown(r.stop);
    await Future<void>.delayed(Duration.zero);

    expect(r.deviceModel, isNull);
  });

  test('model names are cleaned to what the server accepts', () {
    expect(FrameReporter.cleanModel('Galaxy/A10  (2019)'), 'Galaxy A10 (2019)');
    expect(FrameReporter.cleanModel('   '), isNull);
    expect(FrameReporter.cleanModel(null), isNull);
    expect(FrameReporter.cleanModel('x' * 80)!.length, 60);
    expect(FrameReporter.cleanModel('Redmi Note 8 Pro'), 'Redmi Note 8 Pro');
  });

  test('a failing send never throws', () async {
    final r = FrameReporter(
      send: (_) async => throw StateError('offline'),
      build: 'abc1234',
      platform: 'android',
      refreshRateHz: () => 60,
    );
    for (int i = 0; i < 200; i++) {
      r.addFrame(build: _ms(4), raster: _ms(4));
    }

    await expectLater(r.flush(), completes);
  });
}
