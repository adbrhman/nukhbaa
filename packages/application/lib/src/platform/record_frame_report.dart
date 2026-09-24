/// Use-case: keep one app session's frame counts (migration 0070).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/frame_report_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Keeps a signed-in player's frame report, for the smoothness the admin
/// dashboard shows across every device.
///
/// A report that cannot be true -- more slow frames than frames, a refresh
/// rate no display has, a made-up platform -- is refused rather than
/// averaged in: it would be noise, and the app never waits on the answer.
///
/// Never throws; returns a typed [Result].
final class RecordFrameReport {
  /// Creates the use-case over its collaborators.
  const RecordFrameReport({
    required FrameReportRepository reports,
    required Clock clock,
  }) : _reports = reports,
       _clock = clock;

  final FrameReportRepository _reports;
  final Clock _clock;

  /// The platforms the app ships on.
  static const Set<String> platforms = <String>{'android', 'ios', 'web'};

  /// The fastest display a report may claim.
  static const int maxRefreshRateHz = 480;

  /// The most frames one session may report, so no report outweighs the
  /// rest.
  static const int maxFrames = 10000000;

  /// The slowest frame a report may claim (ten minutes).
  static const int maxFrameMs = 600000;

  static final RegExp _build = RegExp(r'^[0-9A-Za-z._-]{1,40}$');

  /// Keeps [report] from [principal].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required FrameReport report,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final bool valid =
        _build.hasMatch(report.build) &&
        platforms.contains(report.platform) &&
        report.refreshRateHz >= 1 &&
        report.refreshRateHz <= maxRefreshRateHz &&
        report.frames >= 1 &&
        report.frames <= maxFrames &&
        report.slowFrames >= 0 &&
        report.slowFrames <= report.frames &&
        report.frozenFrames >= 0 &&
        report.frozenFrames <= report.slowFrames &&
        report.worstFrameMs >= 0 &&
        report.worstFrameMs <= maxFrameMs;
    if (!valid) {
      return const Result.err(
        AppError.validation('perf.invalid_report', 'Invalid frame report'),
      );
    }
    return _reports.record(
      userId: principal.userId,
      report: report,
      reportedAt: _clock.nowUtc(),
    );
  }
}
