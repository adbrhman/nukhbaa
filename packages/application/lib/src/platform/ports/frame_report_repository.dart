import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One app session's frame counts, as the app reports them (migration 0070).
///
/// A frame is slow when its build or raster phase ran past one refresh
/// interval of the display it was drawn on (16.7 ms at 60 Hz, 8.3 ms at
/// 120 Hz), frozen when either ran past 700 ms. Frozen frames are also slow.
final class FrameReport {
  /// Creates a report.
  const FrameReport({
    required this.build,
    required this.platform,
    required this.refreshRateHz,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
    required this.worstFrameMs,
    this.deviceModel,
  });

  /// The build's short commit sha, as the OTA check knows it.
  final String build;

  /// `android`, `ios` or `web`.
  final String platform;

  /// The display's refresh rate the budget was measured against.
  final int refreshRateHz;

  /// Frames drawn in the session.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms (a subset of [slowFrames]).
  final int frozenFrames;

  /// The slowest frame's longer phase, in milliseconds.
  final int worstFrameMs;

  /// The device's maker and model (`samsung SM-A105F`); null when the app
  /// could not read it or predates migration 0071.
  final String? deviceModel;
}

/// Summed [FrameReport]s over a window: for every build ([build] is null),
/// or for one build on one platform.
final class FrameTotals {
  /// Creates the totals.
  const FrameTotals({
    required this.build,
    required this.reports,
    required this.users,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
    required this.worstFrameMs,
    required this.lastReportedAt,
    this.platform,
  });

  /// The build these totals cover; null for all builds together.
  final String? build;

  /// The platform of this row (`android`, `ios` or `web`), so one build
  /// reads once for each platform it ran on; null for all builds together.
  final String? platform;

  /// Session reports summed.
  final int reports;

  /// Distinct users behind them.
  final int users;

  /// Frames drawn.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms.
  final int frozenFrames;

  /// The slowest frame seen, in milliseconds.
  final int worstFrameMs;

  /// The newest report summed; null when there was none.
  final DateTime? lastReportedAt;
}

/// Summed [FrameReport]s of one device model over a window.
final class DeviceTotals {
  /// Creates the totals.
  const DeviceTotals({
    required this.deviceModel,
    required this.reports,
    required this.users,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
  });

  /// The maker and model.
  final String deviceModel;

  /// Session reports summed.
  final int reports;

  /// Distinct users behind them.
  final int users;

  /// Frames drawn.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms.
  final int frozenFrames;
}

/// Port over `ops.frame_reports` (migrations 0070, 0071).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class FrameReportRepository {
  /// Keeps [report] from [userId], received at [reportedAt].
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  });

  /// Totals of the reports received since [since]: first all builds
  /// together, then one row per build and platform, newest first, for the
  /// [maxBuilds] newest builds (a build's platforms count as one build).
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  });

  /// Per device model since [since], the least smooth first, at most
  /// [limit]; a model only when at least [minUsers] distinct users report
  /// it, so no row describes one person's phone.
  Future<Result<List<DeviceTotals>>> devices({
    required DateTime since,
    required int minUsers,
    required int limit,
  });
}
