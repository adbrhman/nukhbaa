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
}

/// Summed [FrameReport]s over a window: for every build ([build] is null),
/// or for one build.
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
  });

  /// The build these totals cover; null for all builds together.
  final String? build;

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

/// Port over `ops.frame_reports` (migration 0070).
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
  /// together, then one row per build, newest first, at most [maxBuilds].
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  });
}
