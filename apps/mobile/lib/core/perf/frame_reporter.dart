/// Frame smoothness from every device (migration 0070): the app counts its
/// own frames and, when it goes to the background, sends one report of the
/// session. The admin dashboard shows the totals.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Counts frames against the display's own refresh interval and reports
/// each session once, when the app leaves the foreground.
///
/// A frame is slow when its build or raster phase ran past one refresh
/// interval (16.7 ms at 60 Hz, 8.3 ms at 120 Hz): the two phases run in
/// parallel on different threads, so the longer one is what the eye sees.
/// It is frozen past 700 ms. Nothing about screens or content is kept.
class FrameReporter with WidgetsBindingObserver {
  /// Creates a reporter that hands each report to [send].
  ///
  /// A build without a [build] sha (a local or test build) never sends.
  FrameReporter({
    required Future<void> Function(FrameReportDto report) send,
    required this.build,
    required this.platform,
    int Function()? refreshRateHz,
  }) : _send = send,
       _refreshRateHz = refreshRateHz ?? _displayRefreshRate;

  /// The build's short commit sha; empty in local and test builds.
  final String build;

  /// `android`, `ios` or `web`.
  final String platform;

  final Future<void> Function(FrameReportDto report) _send;
  final int Function() _refreshRateHz;

  /// Past this, a frame counts as frozen.
  static const Duration frozenAfter = Duration(milliseconds: 700);

  /// A session shorter than this (a couple of seconds) is not reported:
  /// too few frames to say anything.
  static const int minFrames = 120;

  int _frames = 0;
  int _slow = 0;
  int _frozen = 0;
  int _worstMicros = 0;
  bool _started = false;

  /// Frames counted since the last report.
  int get frames => _frames;

  /// The platform this build runs on, in the server's words.
  static String get currentPlatform => kIsWeb
      ? 'web'
      : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  static int _displayRefreshRate() {
    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    final double hz = displays.isEmpty ? 60 : displays.first.refreshRate;
    return hz.isFinite && hz >= 1 ? hz.round().clamp(1, 480) : 60;
  }

  /// Starts counting and listening for the app leaving the foreground.
  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops counting. Frames not yet reported are dropped.
  void stop() {
    if (!_started) return;
    _started = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      addFrame(build: t.buildDuration, raster: t.rasterDuration);
    }
  }

  /// Counts one frame whose phases took [build] and [raster].
  void addFrame({required Duration build, required Duration raster}) {
    final int micros = math.max(build.inMicroseconds, raster.inMicroseconds);
    final int budget = (1000000 / _refreshRateHz()).round();
    _frames++;
    if (micros > budget) _slow++;
    if (micros > frozenAfter.inMicroseconds) _frozen++;
    if (micros > _worstMicros) _worstMicros = micros;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }

  /// Sends what was counted since the last report, then starts over.
  /// Never throws: a lost report costs nothing the user sees.
  Future<void> flush() async {
    if (build.isEmpty || _frames < minFrames) return;
    final FrameReportDto report = FrameReportDto(
      build: build,
      platform: platform,
      refreshRateHz: _refreshRateHz(),
      frames: _frames,
      slowFrames: _slow,
      frozenFrames: _frozen,
      worstFrameMs: (_worstMicros / 1000).round(),
    );
    _frames = 0;
    _slow = 0;
    _frozen = 0;
    _worstMicros = 0;
    try {
      await _send(report);
    } on Object catch (_) {
      // Best effort by design.
    }
  }
}
